# -*- coding: utf-8 -*- {{{
# vim: set fenc=utf-8 ft=python sw=4 ts=4 sts=4 et:

# Copyright (c) 2016, Battelle Memorial Institute
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
import csv
import numpy as np
from volttron.platform.vip.agent import Agent, Core
from volttron.platform.agent import utils
from volttron.platform.agent.math_utils import mean, stdev
from volttron.platform.agent.base_market_agent import MarketAgent
from volttron.platform.agent.base_market_agent.poly_line import PolyLine
from volttron.platform.agent.base_market_agent.point import Point
from volttron.platform.agent.base_market_agent.buy_sell import SELLER
from volttron.platform.agent.base_market_agent.buy_sell import BUYER

_log = logging.getLogger(__name__)
utils.setup_logging()
__version__ = "0.1"


def building_demand(config_path, **kwargs):
    """Parses the uncontrollable load agent configuration and returns an instance of
    the agent created using that configuration.

    :param config_path: Path to a configuration file.

    :type config_path: str
    :returns: Market Service Agent
    :rtype: MarketServiceAgent
    """

    _log.debug("Starting the uncontrol agent")
    try:
        config = utils.load_config(config_path)
    except StandardError:
        config = {}

    if not config:
        _log.info("Using defaults for starting configuration.")
    agent_name = config.get("agent_name", "building_demand")
    base_name = config.get('market_name', 'electric')
    market_name = []
    building_demand = {}
    demand_csv = config.get("demand_csv", "/home/volttron/transactivecontrol1/MarketAgents/BuildingDemand/building_demand.csv")
    with open (demand_csv, 'rb') as f:
        reader = csv.reader(f)
        for line in reader:
            building_demand[line[0]] = sorted(line[1:])

    _log.debug("building demand: {}".format(building_demand))
    price_multiplier = config.get('price_multiplier', 2.0)
    default_min_price = config.get('default_min_price', 0.01)
    default_max_price = config.get('default_min_price', 100.0)
    for i in range(24):
        market_name.append('_'.join([base_name, str(i)]))

    verbose_logging = config.get('verbose_logging', True)

    return BuildingDemand(agent_name, market_name, verbose_logging, building_demand,
                          price_multiplier, default_min_price, default_max_price, **kwargs)


class BuildingDemand(MarketAgent):
    def __init__(self, agent_name, market_name, verbose_logging, building_demand,
                 price_multiplier, default_min_price, default_max_price, **kwargs):
        super(BuildingDemand, self).__init__(verbose_logging, **kwargs)
        self.market_name = market_name

        self.building_demand = building_demand
        self.price_multiplier = price_multiplier
        self.default_max_price = default_max_price
        self.default_min_price = default_min_price
        self.current_hour = None
        self.agent_name = agent_name

        self.prices = []
        for market in self.market_name:
            self.join_market(market, BUYER, None, self.offer_callback,
                             None, self.price_callback, self.error_callback)

    @Core.receiver('onstart')
    def setup(self, sender, **kwargs):
        """
        Set up subscriptions for demand limiting case.
        :param sender:
        :param kwargs:
        :return:
        """
        self.vip.pubsub.subscribe(peer='pubsub',
                                  prefix='mixmarket/start_new_cycle',
                                  callback=self.get_prices)

    def get_prices(self, peer, sender, bus, topic, headers, message):
        _log.debug("Get prices prior to market start.")

        # Store received prices so we can use it later when doing clearing process
        self.current_hour = message['hour']
        self.prices = message['prices']  # Array of price

    def offer_callback(self, timestamp, market_name, buyer_seller):
        index = self.market_name.index(market_name)

        load_index = self.determine_load_index(index)
        demand_curve = self.create_demand_curve(index)
        result, message = self.make_offer(market_name, buyer_seller, demand_curve)

        _log.debug("{}: result of the make offer {} at {}".format(self.agent_name,
                                                                  result,
                                                                  timestamp))

    def determine_load_index(self, index):
        if self.current_hour is None:
            return index
        if index == 0:
            _hour = self.current_hour + 1 if self.current_hour + 1 < 24 else 0
        elif index + self.current_hour + 1 < 24:
            _hour = self.current_hour + index + 1
        else:
            _hour = self.current_hour + index + 1 - 24 if self.current_hour + index + 1 - 24 < 24 else 0
        return _hour

    def create_demand_curve(self, index):
        demand_curve = PolyLine()
        price_min, price_max = self.determine_prices()
        quantity = self.determin_quantity(index)
        price = np.linspace(price_max, price_min, num=len(quantity)).tolist()
        for pr, qt in zip(price, quantity):
            demand_curve.add(Point(price=pr, quantity=qt))

        _log.debug("{}: demand curve for {} - {}".format(self.agent_name,
                                                         self.market_name[index],
                                                         demand_curve.points))
        return demand_curve

    def determine_prices(self):
        try:
            if self.prices:
                avg_price = mean(self.prices)
                std_price = stdev(self.prices)
                price_min = avg_price - self.price_multiplier * std_price
                price_max = avg_price + self.price_multiplier * std_price
            else:
                price_min = self.default_min_price
                price_max = self.default_max_price
        except:
            price_min = self.default_min_price
            price_max = self.default_max_price
        return price_min, price_max

    def determine_quantities(self, index):
        load_index = self.determine_load_index(index)
        return self.building_demand[load_index]

    def price_callback(self, timestamp, market_name, buyer_seller, price, quantity):
        _log.debug("{}: cleared price ({}, {}) for {} as {} at {}".format(self.agent_name,
                                                                          price,
                                                                          quantity,
                                                                          market_name,
                                                                          buyer_seller,
                                                                          timestamp))
        index = self.market_name.index(market_name)

    def error_callback(self, timestamp, market_name, buyer_seller, error_code, error_message, aux):
        _log.debug("{}: error for {} as {} at {} - Message: {}".format(self.agent_name,
                                                                       market_name,
                                                                       buyer_seller,
                                                                       timestamp,
                                                                       error_message))


def main():
    """Main method called to start the agent."""
    utils.vip_main(building_demand, version=__version__)


if __name__ == '__main__':
    # Entry point for script
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass