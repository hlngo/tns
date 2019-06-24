# -*- coding: utf-8 -*- {{{
# vim: set fenc=utf-8 ft=python sw=4 ts=4 sts=4 et:

# Copyright (c) 2017, Battelle Memorial Institute
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation
# are those of the authors and should not be interpreted as representing
# official policies, either expressed or implied, of the FreeBSD
# Project.
#
# This material was prepared as an account of work sponsored by an
# agency of the United States Government.  Neither the United States
# Government nor the United States Department of Energy, nor Battelle,
# nor any of their employees, nor any jurisdiction or organization that
# has cooperated in the development of these materials, makes any
# warranty, express or implied, or assumes any legal liability or
# responsibility for the accuracy, completeness, or usefulness or any
# information, apparatus, product, software, or process disclosed, or
# represents that its use would not infringe privately owned rights.
#
# Reference herein to any specific commercial product, process, or
# service by trade name, trademark, manufacturer, or otherwise does not
# necessarily constitute or imply its endorsement, recommendation, or
# favoring by the United States Government or any agency thereof, or
# Battelle Memorial Institute. The views and opinions of authors
# expressed herein do not necessarily state or reflect those of the
# United States Government or any agency thereof.
#
# PACIFIC NORTHWEST NATIONAL LABORATORY
# operated by BATTELLE for the UNITED STATES DEPARTMENT OF ENERGY
# under Contract DE-AC05-76RL01830

# }}}

import sys
import logging
import dateutil.tz
from volttron.platform.agent import utils
from volttron.platform.messaging import topics
from volttron.platform.agent.math_utils import mean, stdev
from volttron.platform.vip.agent import Agent, Core
from volttron.platform.jsonrpc import RemoteError
from volttron.platform.vip.agent import errors
from volttron.platform.agent.base_market_agent import MarketAgent
from volttron.platform.agent.base_market_agent.poly_line import PolyLine
from volttron.platform.agent.base_market_agent.point import Point
from volttron.platform.agent.base_market_agent.buy_sell import BUYER
from pnnl.models.rtusimple import FirstOrderZone
import numpy as np
import gevent
from dateutil import parser

_log = logging.getLogger(__name__)
utils.setup_logging()
__version__ = "0.2"
TIMEZONE = "US/Pacific"


def rtu_agent(config_path, **kwargs):
    """Parses the Electric Meter Agent configuration and returns an instance of
    the agent created using that configuation.

    :param config_path: Path to a configuation file.

    :type config_path: str
    :returns: Market Service Agent
    :rtype: MarketServiceAgent
    """
    try:
        config = utils.load_config(config_path)
    except StandardError:
        config = {}

    if not config:
        _log.info("Using defaults for starting configuration.")

    base_name = config.get('market_name', 'electric')
    market_name = []
    for i in range(24):
        market_name.append('_'.join([base_name, str(i)]))
    c1 = config.get('c1')
    c2 = config.get('c2')
    c3 = config.get('c3')
    c = config.get('c')
    heartbeat_period = config.get('heartbeat_period', 300)
    hvac_avail = config.get("occupancy_schedule")
    tMinAdj = config.get('tMin', 0)
    tMaxAdj = config.get('tMax', 0)
    sim_flag = config.get('sim_flag', False)
    tIn = config.get('tIn', 0)

    Qrate = config.get("Qrate", 0)
    agent_name = config.get('agent_name')
    actuator = config.get('actuator', 'platform.actuator')
    mode = config.get('mode')
    device_points = config.get("device_points")
    setpoint = config.get('setpoint')
    activate_topic = "/".join([config.get("building", agent_name), "actuate"])
    setpoint_mode = config.get("setpoint_mode", 0)

    price_multiplier = config.get('price_multiplier', 2)
    default_min_price = config.get('default_min_price', 0.01)
    default_max_price = config.get('default_max_price', 0.1)
    tMaxUnoc = config.get('tMaxUnoc', 26.7)
    device_topic = topics.DEVICES_VALUE(campus=config.get('campus', ''),
                                        building=config.get('building', ''),
                                        unit=config.get('device', ''),
                                        path='',
                                        point='all')

    base_rpc_path = topics.RPC_DEVICE_PATH(campus=config.get("campus", ""),
                                           building=config.get("building", ""),
                                           unit=config.get("device", ""),
                                           path="",
                                           point=setpoint)

    verbose_logging = config.get('verbose_logging', True)

    return RTUAgent(market_name, agent_name, c1, c2, c3, c, tMinAdj,
                    tMaxAdj, tMaxUnoc, tIn, Qrate, verbose_logging,
                    device_topic, hvac_avail, device_points,
                    base_rpc_path, activate_topic, actuator, mode, setpoint_mode,
                    sim_flag, heartbeat_period, price_multiplier,
                    default_min_price, default_max_price, **kwargs)


def temp_f2c(rawtemp):
    return (rawtemp - 32) / 9 * 5


def temp_c2f(rawtemp):
    return 1.8 * rawtemp + 32.0


def clamp(value, x1, x2):
    min_value = min(abs(x1), abs(x2))
    max_value = max(abs(x1), abs(x2))
    value = abs(value)
    return min(max(value, min_value), max_value)


def ease(target, current, limit):
    return current - np.sign(current - target) * min(abs(current - target), abs(limit))


class RTUAgent(MarketAgent, FirstOrderZone):
    """
    The SampleElectricMeterAgent serves as a sample of an electric meter that
    sells electricity for a single building at a fixed price.
    """

    def __init__(self, market_name, agent_name, c1, c2, c3, c,
                 tMinAdj, tMaxAdj, tMaxUnoc, tIn, Qrate,
                 verbose_logging, device_topic, hvac_avail,
                 device_points, base_rpc_path, activate_topic,
                 actuator, mode, setpoint_mode, sim_flag, heartbeat_period,
                 price_multiplier, default_min_price, default_max_price,
                 **kwargs):
        super(RTUAgent, self).__init__(verbose_logging, **kwargs)
        self.market_name = market_name
        self.agent_name = agent_name
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
        self.c = c
        self.hvac_status = 0
        self.hvac_avail = hvac_avail
        self.tOut = 32
        self.zone_airflow = 10
        self.zone_datemp = 12.78

        self.off = [0] * 24
        self.on = [0] * 24
        self.offmin = 5
        self.onmin = 0
        self.tNomAdj = tIn
        self.temp_stpt = self.tNomAdj
        self.tIn = self.tNomAdj
        self.demand_curve = None
        self.tMinAdj = tMinAdj
        self.tMaxAdj = tMaxAdj
        self.tsets = np.linspace(self.tMaxAdj, self.tMinAdj, 11)
        self.tMaxAdjUnoc = tMaxUnoc
        self.default = None
        self.current_hour = None
        self.current_minute = None
        self.actuator = actuator
        self.mode = mode

        self.sim_flag = sim_flag
        self.Qrate = Qrate
        _log.debug("{} - qrate: {}".format(self.agent_name, self.Qrate))
        self.current_price = None
        self.current_hour_price = None
        if self.sim_flag:
            self.actuate_enabled = 1
        else:
            self.actuate_enabled = 0

        self.setpoint_offset = 0.0

        if isinstance(setpoint_mode, dict):
            self.mode_status = True
            self.status_point = setpoint_mode["point"]
            self.setpoint_mode_true_offset = setpoint_mode["true_value"]
            self.setpoint_mode_false_offset = setpoint_mode["false_value"]
        else:
            self.mode_status = False

        self.device_topic = device_topic

        self.actuator_topic = base_rpc_path
        self.activate_topic = activate_topic
        self.heartbeat_period = heartbeat_period

        # Parent device point mapping (AHU level points)
        self.supply_fan_status = device_points.get('supply_fan_status', 'SupplyFanStatus')

        # Device point mapping (VAV level points)
        self.rtu_status_name = device_points.get("rtu_status", "FirstStageCooling")
        self.zone_temp_name = device_points.get("zone_temperature", "ZoneTemperature")
        self.outdoor_air_temperature = device_points.get("outdoor_air_temperature", "OutdoorAirTemperature")
        self.oat_predictions = []

        self.price_multiplier = price_multiplier
        self.default_min_price = default_min_price
        self.default_max_price = default_max_price
        self.update_flag = []
        self.demand_curve = []
        self.prices = []
        self.temp = []
        self.temp.append(self.tIn)
        for market in self.market_name:
            self.join_market(market, BUYER, None, self.offer_callback, None, self.price_callback, self.error_callback)
            self.update_flag.append(False)
            self.temp.append(self.tIn)
            self.demand_curve.append(PolyLine())

    @Core.receiver('onstart')
    def setup(self, sender, **kwargs):
        _log.debug('Subscribing to ' + self.device_topic)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix=self.device_topic,
                                  callback=self.update_zone_state)
        _log.debug('Subscribing to ' + self.activate_topic)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix=self.activate_topic,
                                  callback=self.update_actuation_state)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix='mixmarket/start_new_cycle',
                                  callback=self.get_prices)
        try:
            self.temp_stpt = self.vip.rpc.call(self.actuator,
                                               'get_point',
                                               self.actuator_topic).get(timeout=10)
        except (RemoteError, gevent.Timeout, errors.VIPError) as ex:
            _log.warning("Failed to get {} - ex: {}".format(self.actuator_topic, str(ex)))
            self.temp_stpt = self.tNomAdj
        if self.heartbeat_period is not None:
            _log.debug('Setup periodic actuation at rate:  {}'.format(self.heartbeat_period))
            self.core.periodic(self.heartbeat_period, self.update_demand_actuate, wait=self.heartbeat_period)

    def get_prices(self, peer, sender, bus, topic, headers, message):

        _log.debug("Get prices prior to market start.")
        current_hours_price = message['hour']

        # Store received prices so we can use it later when doing clearing process
        if self.prices:
            if current_hours_price != self.current_hour_price:
                self.current_price = self.prices[0]
        self.current_hour_price = current_hours_price
        self.oat_predictions = []
        oat_predictions = message.get("temp", [])

        self.oat_predictions = oat_predictions
        self.prices = message['prices']  # Array of prices

    def offer_callback(self, timestamp, market_name, buyer_seller):
        index = self.market_name.index(market_name)
        if index > 0:
            while not self.update_flag[index - 1]:
                gevent.sleep(1)
        if index == 0:
            run_time = int(60 - self.current_minute)
            self.temp[0], self.on[0], self.off[0] = self.get_t(self.tIn, self.temp_stpt, self.tOut,
                                                               self.current_hour, self.on[0], self.off[0], run_time)
        temp = self.temp[index]
        oat = self.oat_predictions[index] if self.oat_predictions else self.tOut
        hvac_index = self.determine_hvac_index(index)
        demand_curve = self.create_demand_curve(index, hvac_index, temp, oat)
        self.demand_curve[index] = demand_curve
        result, message = self.make_offer(market_name, buyer_seller, demand_curve)
        _log.debug('{}: result of the make offer {} at {}'.format(self.agent_name,
                                                                  result,
                                                                  timestamp))
        if not result:
            _log.debug('{}: maintain old set point {}'.format(self.agent_name,
                                                              self.temp_stpt))
        if index == len(self.market_name) - 1:
            for i in range(len(self.market_name)):
                self.update_flag[i] = False

    def create_demand_curve(self, index, hvac_index, temp, oat):
        _log.debug("{} debug demand_curve1 - index: {} - hvac_index: {}".format(self.agent_name, index, hvac_index))
        demand_curve = PolyLine()
        prices = self.determine_prices()

        for i in range(len(prices)):
            if self.hvac_avail[hvac_index]:
                temp_stpt = self.tsets[i]
            else:
                temp_stpt = self.tMaxAdjUnoc
            ontime = self.on[index]
            offtime = self.off[index]
            on = 0
            t = float(temp)
            for j in range(60):
                if ontime and t < temp_stpt - 0.55 and ontime > self.onmin:
                    offtime = 1
                    ontime = 0
                    t = self.getT(t, oat, 0, hvac_index)
                elif ontime:
                    offtime = 0
                    ontime += 1
                    on += 1
                    t = self.getT(t, oat, 1, hvac_index)
                elif offtime and t > temp_stpt + 0.55 and offtime > self.offmin:
                    offtime = 0
                    ontime = 1
                    on += 1
                    t = self.getT(t, oat, 1, hvac_index)
                elif offtime:
                    offtime += 1
                    ontime = 0
                    t = self.getT(t, oat, 0, hvac_index)
                _log.debug(
                    "{} Debug demand_curve2 - t: {} - temp_stpt: {} - ontime: {} - on: {}".format(self.agent_name, t,
                                                                                                  temp_stpt, ontime,
                                                                                                  on))

            demand_curve.add(Point(price=prices[i], quantity=on / 60.0 * self.Qrate))
            _log.debug("{} debug demand_curve3 on {} - curve: {}".format(self.agent_name, on, demand_curve.points))
        _log.debug("{} debug demand_curve4 - curve: {}".format(self.agent_name, demand_curve.points))
        return demand_curve

    def determine_prices(self):
        if self.prices:
            avg_price = mean(self.prices)
            std_price = stdev(self.prices)
            price_min = avg_price - self.price_multiplier * std_price
            price_max = avg_price + self.price_multiplier * std_price
            _log.debug('{}: price debug avg {} - std_dev: {} - min: {} - max: {}'
                       .format(self.agent_name, avg_price, std_price, price_min, price_max))
        else:
            price_min = self.default_min_price
            price_max = self.default_max_price
        price_array = np.linspace(price_min, price_max, 11)
        return price_array

    def determine_hvac_index(self, index):
        if self.current_hour is None:
            return index
        # if index == 0:
        #   return self.current_hour + 1
        elif index + self.current_hour + 1 < 24:
            return self.current_hour + index + 1
        else:
            return self.current_hour + index + 1 - 24

    def update_zone_state(self, peer, sender, bus, topic, headers, message):
        """
        Subscribe to device data from message bus
        :param peer:
        :param sender:
        :param bus:
        :param topic:
        :param headers:
        :param message:
        :return:
        """
        _log.debug('{} received zone info'.format(self.agent_name))
        info = message[0]
        self.rtu_status = info[self.rtu_status_name]
        self.hvac_status = info[self.supply_fan_status]
        current_time = parser.parse(headers["Date"])
        to_zone = dateutil.tz.gettz(TIMEZONE)
        current_time = current_time.astimezone(to_zone)

        self.tOut = info[self.outdoor_air_temperature]
        self.tIn = info[self.zone_temp_name]
        self.current_hour = current_time.hour
        self.current_minute = current_time.hour

        if self.rtu_status > 0:
            self.on[0] = self.on[0] + 1
            self.off[0] = 0
        else:
            self.off[0] = self.off[0] + 1
            self.on[0] = 0

        if self.mode_status:
            if info[self.status_point]:
                self.setpoint_offset = self.setpoint_mode_true_offset
                _log.debug("Setpoint offset: {}".format(self.setpoint_offset))
            else:
                self.setpoint_offset = self.setpoint_mode_false_offset
                _log.debug("Setpoint offset: {}".format(self.setpoint_offset))

    def update_actuation_state(self, peer, sender, bus, topic, headers, message):
        """
        Subscribe to device data from message bus.
        :param peer:
        :param sender:
        :param bus:
        :param topic:
        :param headers:
        :param message:
        :return:
        """
        _log.debug('{} received update actuation.'.format(self.agent_name))
        _log.debug('Current actuation state: {} - '
                   'update actuation state: {}'.format(self.actuate_enabled, message))
        if not self.actuate_enabled and message:
            try:
                self.default = self.vip.rpc.call(self.actuator, 'get_point', self.actuator_topic).get(timeout=10)
            except (RemoteError, gevent.Timeout, errors.VIPError) as ex:
                _log.warning('Failed to get {} - ex: {}'.format(self.actuator_topic, str(ex)))

        self.actuate_enabled = message
        if not self.actuate_enabled:
            if self.mode == 1:
                set_value = None
            elif self.default is not None:
                set_value = self.default
            else:
                return
            try:
                self.vip.rpc.call(self.actuator, 'set_point', self.agent_name,
                                  self.actuator_topic, set_value).get(timeout=10)
            except (RemoteError, gevent.Timeout, errors.VIPError) as ex:
                _log.warning('Failed to set {} to {}: {}'.format(self.actuator_topic, set_value, str(ex)))

    def update_setpoint(self, hvac_index, price):
        if self.hvac_avail[hvac_index]:
            prices = self.determine_prices()
            self.temp_stpt = clamp(np.interp(price, prices, self.tsets), self.tMinAdj, self.tMaxAdj)
        else:
            self.temp_stpt = self.tMaxAdjUnoc
        _log.debug("Setpoint calculation: {}".format(self.temp_stpt))

    def price_callback(self, timestamp, market_name, buyer_seller, price, quantity):
        _log.debug('{} - price of {} for market: {}'.format(self.agent_name, price, market_name))
        index = self.market_name.index(market_name)
        hvac_index = self.determine_hvac_index(index)
        if price is not None and index < 23:
            self.update_t(index, hvac_index, price)

    def update_t(self, index, hvac_index, price):
        temp = self.temp[index]
        oat = self.oat_predictions[index] if self.oat_predictions else self.tOut
        if self.hvac_avail[hvac_index]:
            prices = self.determine_prices()
            temp_stpt = clamp(np.interp(price, prices, self.tsets), self.tMinAdj, self.tMaxAdj)
        else:
            temp_stpt = self.tMaxAdjUnoc
        ontime = self.on[index]
        offtime = self.off[index]
        temp, ontime, offtime = self.get_t(temp, temp_stpt, oat, hvac_index, ontime, offtime, 60)
        _log.debug("Temperature calculation before clamp: {}".format(temp))
        self.temp[index + 1] = clamp(temp, self.tMinAdj, self.tMaxAdj)
        self.on[index + 1] = ontime
        self.off[index + 1] = offtime
        self.update_flag[index] = True

    def get_t(self, temp, temp_stpt, oat, hvac_index, ontime, offtime, run_time):
        for i in range(run_time):
            if ontime and temp < temp_stpt - 0.55 and ontime > self.onmin:
                offtime = 1
                ontime = 0
                temp = self.getT(temp, oat, 0, hvac_index)
            elif ontime:
                offtime = 0
                ontime += 1
                temp = self.getT(temp, oat, 1, hvac_index)
            elif offtime and temp > temp_stpt + 0.55 and offtime > self.offmin:
                offtime = 0
                ontime = 1
                temp = self.getT(temp, oat, 1, hvac_index)
            elif offtime:
                offtime += 1
                ontime = 0
                temp = self.getT(temp, oat, 0, hvac_index)
        return temp, ontime, offtime

    def error_callback(self, timestamp, market_name, buyer_seller, error_code, error_message, aux):
        _log.debug('{} - error for Market: {} {}, Message: {}'.format(self.agent_name,
                                                                      market_name,
                                                                      buyer_seller, aux))

    def update_demand_actuate(self):
        hvac_index = self.current_hour
        if hvac_index is None:
            return
        _log.debug(
            "{} actuate - saved hour: {} - current hour {} - price {}".format(self.agent_name,
                                                                              self.current_hour_price,
                                                                              self.current_hour,
                                                                              self.current_price))
        if self.current_price is not None and self.hvac_avail[hvac_index]:
            if self.current_hour_price == self.current_hour:
                self.update_setpoint(hvac_index, self.current_price)
        elif not self.hvac_avail[hvac_index]:
            self.temp_stpt = self.tMaxAdjUnoc
            if not self.sim_flag:
                return
        self.actuate_setpoint()

    def actuate_setpoint(self):
        temp_stpt = self.temp_stpt - self.setpoint_offset
        if self.actuate_enabled:
            _log.debug("{} - setting {} with value {}".format(self.agent_name, self.actuator_topic, temp_stpt))
            self.vip.rpc.call(self.actuator,
                              'set_point',
                              self.agent_name,
                              self.actuator_topic,
                              temp_stpt).get(timeout=10)


def main():
    """Main method called to start the agent."""
    utils.vip_main(rtu_agent, version=__version__)


if __name__ == '__main__':
    # Entry point for script
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
