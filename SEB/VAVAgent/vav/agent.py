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
# 'AS IS' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
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
import numpy as np
import gevent
from dateutil import parser
import dateutil.tz
from volttron.platform.agent.math_utils import mean, stdev
from volttron.platform.agent import utils
from volttron.platform.messaging import topics
from volttron.platform.vip.agent import Agent, Core
from volttron.platform.jsonrpc import RemoteError
from volttron.platform.vip.agent import errors
from volttron.platform.agent.base_market_agent import MarketAgent
from volttron.platform.agent.base_market_agent.poly_line import PolyLine
from volttron.platform.agent.base_market_agent.point import Point
from volttron.platform.agent.base_market_agent.buy_sell import BUYER
from pnnl.models.firstorderzone import FirstOrderZone

_log = logging.getLogger(__name__)
utils.setup_logging()
__version__ = '0.1'
TIMEZONE = "US/Pacific"


def vav_agent(config_path, **kwargs):
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
        _log.info('Using defaults for starting configuration.')
    base_name = config.get('market_name', 'air')
    market_name = []
    for i in range(24):
        market_name.append('_'.join([base_name, str(i)]))
    c1 = config.get('c1')
    c2 = config.get('c2')
    c3 = config.get('c3')

    tMinAdj = config.get('tMin', 0)
    tMaxAdj = config.get('tMax', 0)
    tMinUnoc = config.get('tMinUnoc', 19.0)
    mDotMin = config.get('mDotMin', 0)
    mDotMax = config.get('mDotMax', 0)
    sim_flag = config.get('sim_flag', False)
    tIn = config.get('tIn', 0)

    agent_name = config.get('agent_name')
    actuator = config.get('actuator', 'platform.actuator')
    mode = config.get('mode')
    device_points = config.get('device_points')
    parent_device_points = config.get('parent_device_points')
    setpoint = config.get('setpoint')
    activate_topic = '/'.join([config.get('building', agent_name), 'actuate'])
    setpoint_mode = config.get('setpoint_mode', 0)

    price_multiplier = config.get('price_multiplier', 2.0)
    default_min_price = config.get('default_min_price', 0.02)
    default_max_price = config.get('default_max_price', 0.04)
    heartbeat_period = config.get('heartbeat_period', 300)
    hvac_avail = config.get("hvac_occupancy_schedule",  [1]*24)

    parent_device_topic = topics.DEVICES_VALUE(campus=config.get('campus', ''),
                                               building=config.get('building', ''),
                                               unit=config.get('parent_device', ''),
                                               path='',
                                               point='all')

    device_topic = topics.DEVICES_VALUE(campus=config.get('campus', ''),
                                        building=config.get('building', ''),
                                        unit=config.get('parent_device', ''),
                                        path=config.get('device', ''),
                                        point='all')

    base_rpc_path = topics.RPC_DEVICE_PATH(campus=config.get('campus', ''),
                                           building=config.get('building', ''),
                                           unit=config.get('parent_device', ''),
                                           path=config.get('device', ''),
                                           point=setpoint)

    verbose_logging = config.get('verbose_logging', True)
    tns_actuate = config.get('tns_actuate', 'tns/actuate')
    return VAVAgent(market_name, agent_name, c1,c2, c3,
                    tMinAdj, tMaxAdj, tMinUnoc, mDotMin, mDotMax,
                    tIn, verbose_logging, device_topic, hvac_avail,
                    device_points, parent_device_topic, parent_device_points,
                    base_rpc_path, activate_topic, actuator, mode, setpoint_mode,
                    sim_flag, heartbeat_period, tns_actuate, price_multiplier,
                    default_min_price, default_max_price, **kwargs)


def temp_f2c(rawtemp):
    return (rawtemp - 32) / 9 * 5


def temp_c2f(rawtemp):
    return 1.8 * rawtemp + 32.0


def flow_cfm2cms(rawflowrate):
    return rawflowrate * 0.00043 * 1.2


def clamp(value, x1, x2):
    min_value = min(abs(x1), abs(x2))
    max_value = max(abs(x1), abs(x2))
    value = abs(value)
    return min(max(value, min_value), max_value)


def ease(target, current, limit):
    return current - np.sign(current - target) * min(abs(current - target), abs(limit))


class VAVAgent(MarketAgent, FirstOrderZone):
    """
    The SampleElectricMeterAgent serves as a sample of an electric meter that
    sells electricity for a single building at a fixed price.
    """

    def __init__(self, market_name, agent_name, c1, c2, c3,
                 tMinAdj, tMaxAdj, tMinUnoc, mDotMin, mDotMax, tIn, verbose_logging,
                 device_topic, hvac_avail, device_points, parent_device_topic, parent_device_points,
                 base_rpc_path, activate_topic, actuator, mode, setpoint_mode, sim_flag,
                 heartbeat_period, tns_actuate, price_multiplier, default_min_price,
                 default_max_price, **kwargs):
        super(VAVAgent, self).__init__(verbose_logging, **kwargs)
        self.market_name = market_name
        self.agent_name = agent_name
        # First order model parameters
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
        self.tOut = 32
        self.zone_airflow = 10
        self.zone_datemp = 12.78
        self.tDel = 0.25
        self.t_ease = 0.25

        self.tNomAdj = tIn
        self.temp_stpt = self.tNomAdj
        self.tIn = self.tNomAdj
        self.temp = []
        self.tMinAdj = tMinAdj
        self.tMaxAdj = tMaxAdj
        self.tsets = np.linspace(self.tMaxAdj, self.tMinAdj, 11)
        self.tMinAdjUnoc = tMinUnoc
        self.mDotMin = mDotMin
        self.mDotMax = mDotMax
        self.qHvacSens = self.zone_airflow * 1006. * (self.zone_datemp - self.tIn)
        self.qMin = min(0, self.mDotMin * 1006. * (self.zone_datemp - self.tIn))
        self.qMax = min(0, self.mDotMax * 1006. * (self.zone_datemp - self.tIn))

        self.default = None
        self.current_hour = None
        self.current_hours_price = None
        self.actuator = actuator
        self.mode = mode

        self.sim_flag = sim_flag
        self.heartbeat_period = heartbeat_period
        self.hvac_status = 0
        self.hvac_avail = hvac_avail
        self.current_price = None
        self.current_hour_price = None
        if self.sim_flag:
            self.actuate_enabled = 1
        else:
            self.actuate_enabled = 0

        self.setpoint_offset = 0.0

        if isinstance(setpoint_mode, dict):
            self.mode_status = True
            self.status_point = setpoint_mode['point']
            self.setpoint_mode_true_offset = setpoint_mode['true_value']
            self.setpoint_mode_false_offset = setpoint_mode['false_value']
        else:
            self.mode_status = False

        self.device_topic = device_topic
        self.parent_device_topic = parent_device_topic
        self.actuator_topic = base_rpc_path
        self.activate_topic = activate_topic
        # Parent device point mapping (AHU level points)

        self.supply_fan_status = parent_device_points.get('supply_fan_status', 'SupplyFanStatus')
        self.outdoor_air_temperature = parent_device_points.get('outdoor_air_temperature', 'OutdoorAirTemperature')
        self.oat_predictions = []

        # Device point mapping (VAV level points)
        self.zone_datemp_name = device_points.get('zone_dat', 'ZoneDischargeAirTemperature')
        self.zone_airflow_name = device_points.get('zone_airflow', 'ZoneAirFlow')
        self.zone_temp_name = device_points.get('zone_temperature', 'ZoneTemperature')
        self.tns_actuate = tns_actuate
        self.price_multiplier = price_multiplier
        self.default_min_price = default_min_price
        self.default_max_price = default_max_price
        self.update_flag = []
        self.demand_curve = []
        self.prices = []
        self.q_clear = [0]
        self.temp = [self.tIn]
        self.q = [0]
        for market in self.market_name:
            self.join_market(market, BUYER, None, self.offer_callback,
                             None, self.price_callback, self.error_callback)
            self.update_flag.append(False)
            self.temp.append(self.tIn)
            self.demand_curve.append(PolyLine())
            self.q_clear.append(0.)
            self.q.append(0.)

    @Core.receiver('onstart')
    def setup(self, sender, **kwargs):
        _log.debug('Subscribing to device' + self.device_topic)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix=self.device_topic,
                                  callback=self.update_zone_state)
        _log.debug('Subscribing to parent' + self.parent_device_topic)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix=self.parent_device_topic,
                                  callback=self.update_state)
        _log.debug('Subscribing to ' + self.activate_topic)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix=self.activate_topic,
                                  callback=self.update_actuation_state)
        _log.debug('Subscribing to ' + self.tns_actuate)
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix=self.tns_actuate,
                                  callback=self.actuate_setpoint)
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
        if not self.sim_flag:
            self.temp_stpt = temp_f2c(self.temp_stpt)
        if self.heartbeat_period is not None:
            _log.debug('Setup periodic actuation at rate:  {}'.format(self.heartbeat_period))
            self.core.periodic(self.heartbeat_period, self.update_demand_actuate, wait=self.heartbeat_period)

    def get_prices(self, peer, sender, bus, topic, headers, message):
        _log.debug("{}: Get prices prior to market start.".format(self.agent_name))
        current_hours_price = message['hour']
        # Store received prices
        if self.prices:
            if current_hours_price != self.current_hour_price:
                self.current_price = self.prices[0]
        self.current_hour_price = current_hours_price
        self.oat_predictions = []
        oat_predictions = message.get("temp", [])
        if self.sim_flag:
            for temp in oat_predictions:
                self.oat_predictions.append(temp_f2c(temp))
        else:
            self.oat_predictions = oat_predictions
        self.prices = message['prices']  # Array of prices

    def offer_callback(self, timestamp, market_name, buyer_seller):
        index = self.market_name.index(market_name)
        if index > 0:
            while not self.update_flag[index - 1]:
                _log.debug("Waiting for flag to update: {}".format(index))
                gevent.sleep(1)

        result, message = self.make_offer(market_name, buyer_seller, self.create_demand_curve(index))
        _log.debug('{}: result of the make offer {} at {}'.format(self.agent_name,
                                                                  result,
                                                                  timestamp))
        if not result:
            _log.debug('{}: maintain old set point {}'.format(self.agent_name,
                                                              self.temp_stpt))
        if index == len(self.market_name) - 1:
            for i in range(len(self.market_name)):
                self.update_flag[i] = False

    def create_demand_curve(self, index):
        hvac_index = self.determine_hvac_index(index)
        demand_curve = PolyLine()
        oat = self.oat_predictions[index] if self.oat_predictions else self.tOut
        prices = self.determine_prices()
        price_max_bound = max(max(prices) + 0.1*max(prices), max(self.prices) + max(self.prices) * 0.1)
        price_min_bound = min(min(prices) + 0.1*min(prices), min(self.prices) - min(self.prices) * 0.1)
        temp = self.temp[index]
        quantities = []
        for i in range(len(prices)):
            if self.hvac_avail[hvac_index]:
                temp_stpt = self.tsets[i]
            else:
                temp_stpt = self.tMinAdjUnoc
            quantity = min(max(self.getM(oat, temp, temp_stpt, hvac_index), self.mDotMin), self.mDotMax)
            quantities.append(quantity)
        demand_curve.add(Point(price=price_max_bound, quantity=min(quantities)))
        prices.sort(reverse=True)
        quantities.sort()
        for i in range(len(prices)):
            demand_curve.add(Point(price=prices[i], quantity=quantities[i]))
        demand_curve.add(Point(price=price_min_bound, quantity=max(quantities)))
        _log.debug("{} debug demand_curve4 - curve: {}".format(self.agent_name, demand_curve.points))
        _log.debug(
            "{} market {} has cleared airflow: {}".format(self.agent_name, index, demand_curve.x(self.prices[index])))
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
        price_array = np.linspace(price_min, price_max, 11).tolist()
        return price_array

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

        if not self.sim_flag:
            self.zone_datemp = temp_f2c(info[self.zone_datemp_name])
            self.zone_airflow = flow_cfm2cms(info[self.zone_airflow_name])
            self.tIn = temp_f2c(info[self.zone_temp_name])
        else:
            self.zone_datemp = info[self.zone_datemp_name]
            self.zone_airflow = info[self.zone_airflow_name]
            self.tIn = info[self.zone_temp_name]
            self.temp[0] = self.tIn

        if self.mode_status:
            if info[self.status_point]:
                self.setpoint_offset = self.setpoint_mode_true_offset
                _log.debug('Setpoint offset: {}'.format(self.setpoint_offset))
            else:
                self.setpoint_offset = self.setpoint_mode_false_offset
                _log.debug('Setpoint offset: {}'.format(self.setpoint_offset))

#       self.q[0] = self.zone_airflow * 1006. * (self.zone_datemp - self.tIn)

    def update_state(self, peer, sender, bus, topic, headers, message):
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
        _log.debug('{} update parent_device: {}'.format(self.agent_name, topic))
        info = message[0]
        current_time = parser.parse(headers["Date"])

        if not self.sim_flag:
            to_zone = dateutil.tz.gettz(TIMEZONE)
            current_time = current_time.astimezone(to_zone)
            self.current_hour = current_time.hour
            self.tOut = temp_f2c(info[self.outdoor_air_temperature])
        else:
            self.current_hour = current_time.hour
            self.tOut = info[self.outdoor_air_temperature]

        self.hvac_status = info[self.supply_fan_status]

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
        _log.debug('{}: update_actuation_state.'.format(self.agent_name))
        _log.debug('{}: current state: {} - updated state: {}'.format(self.agent_name, self.actuate_enabled, message))
        if not self.actuate_enabled and message:
            try:
                self.default = self.vip.rpc.call(self.actuator, 'get_point', self.actuator_topic).get(timeout=10)
            except (RemoteError, gevent.Timeout, errors.VIPError) as ex:
                _log.warning('{}: failed to get {} - ex: {}'.format(self.agent_name,
                                                                    self.actuator_topic,
                                                                    str(ex)))

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

    def update_setpoint(self, price):
        prices = self.determine_prices()
        self.temp_stpt = clamp(np.interp(price, prices, self.tsets), self.tMinAdj, self.tMaxAdj)

        _log.debug("Setpoint calculation: {}".format(self.temp_stpt))

    def update_t(self, index, hvac_index, price):
        if self.hvac_avail[hvac_index]:
            prices = self.determine_prices()            
            self.temp[index+1] = clamp(np.interp(price, prices, self.tsets), self.tMinAdj, self.tMaxAdj)

        else:
            self.temp[index+1] = self.tMinAdjUnoc
        _log.debug("{}: update_Tcalc: {} ".format(self.agent_name, self.temp[index+1]))
        self.update_flag[index] = True

    def determine_hvac_index(self, index):
        if self.current_hour is None:
            return index
        elif index + self.current_hour + 1 < 24:
            return self.current_hour + index + 1
        else:
            return self.current_hour + index + 1 - 24

    def price_callback(self, timestamp, market_name, buyer_seller, price, quantity):
        _log.debug('{} - price of {} - cleared quantity - for market: {}'.format(self.agent_name,
                                                                                 price,
                                                                                 quantity,
                                                                                 market_name))
        index = self.market_name.index(market_name)
        hvac_index = self.determine_hvac_index(index)
        _log.debug("Debug price_callback - market_name: {} - index: {} - price: {} - quantity: {}".format(market_name, index, price, quantity))
        if price is not None:
            self.update_t(index, hvac_index, price)

    def error_callback(self, timestamp, market_name, buyer_seller, error_code, error_message, aux):
        _log.debug('{} - error for Market: {} {}, Message: {}'.format(self.agent_name,
                                                                      market_name,
                                                                      buyer_seller, aux))

    def update_demand_actuate(self):
        hvac_index = self.current_hour if self.current_hour else self.determine_hvac_index(-1)
        _log.debug("Debug update_demand_actuate - saved hour: {} - current hour {} - price {}".format(self.current_hour_price, self.current_hour, self.current_price))
        if self.current_price is not None and self.hvac_avail[hvac_index]:
            if self.current_hour_price == self.current_hour:
                self.update_setpoint(self.current_price)
        elif not self.hvac_avail[hvac_index]:
            self.temp_stpt = self.tMinAdjUnoc
        self.actuate_setpoint()

    def actuate_setpoint(self):
        temp_stpt = self.temp_stpt
        if not self.sim_flag:
            temp_stpt = temp_c2f(temp_stpt)
        temp_stpt = temp_stpt - self.setpoint_offset
        if self.actuate_enabled:
            _log.debug('{} - setting {} with value {}'.format(self.agent_name, self.actuator_topic, temp_stpt))
            try:
                self.vip.rpc.call(self.actuator, 'set_point', self.agent_name,
                                  self.actuator_topic, temp_stpt).get(timeout=10)
            except (RemoteError, gevent.Timeout, errors.VIPError) as ex:
                _log.warning('Failed to set {} to {}: {}'.format(self.actuator_topic, temp_stpt, str(ex)))


def main():
    """Main method called to start the agent."""
    utils.vip_main(vav_agent, version=__version__)


if __name__ == '__main__':
    # Entry point for script
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass