"""
-*- coding: utf-8 -*- {{{
vim: set fenc=utf-8 ft=python sw=4 ts=4 sts=4 et:

Copyright (c) 2019, Battelle Memorial Institute
All rights reserved.

1.  Battelle Memorial Institute (hereinafter Battelle) hereby grants
    permission to any person or entity lawfully obtaining a copy of this
    software and associated documentation files (hereinafter "the Software")
    to redistribute and use the Software in source and binary forms, with or
    without modification.  Such person or entity may use, copy, modify, merge,
    publish, distribute, sublicense, and/or sell copies of the Software, and
    may permit others to do so, subject to the following conditions:

    -   Redistributions of source code must retain the above copyright notice,
        this list of conditions and the following disclaimers.

    -	Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

    -	Other than as used herein, neither the name Battelle Memorial Institute
        or Battelle may be used in any form whatsoever without the express
        written consent of Battelle.

2.	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    ARE DISCLAIMED. IN NO EVENT SHALL BATTELLE OR CONTRIBUTORS BE LIABLE FOR
    ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
    OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
    DAMAGE.

The views and conclusions contained in the software and documentation are those
of the authors and should not be interpreted as representing official policies,
either expressed or implied, of the FreeBSD Project.

This material was prepared as an account of work sponsored by an agency of the
United States Government. Neither the United States Government nor the United
States Department of Energy, nor Battelle, nor any of their employees, nor any
jurisdiction or organization that has cooperated in the development of these
materials, makes any warranty, express or implied, or assumes any legal
liability or responsibility for the accuracy, completeness, or usefulness or
any information, apparatus, product, software, or process disclosed, or
represents that its use would not infringe privately owned rights.

Reference herein to any specific commercial product, process, or service by
trade name, trademark, manufacturer, or otherwise does not necessarily
constitute or imply its endorsement, recommendation, or favoring by the
United States Government or any agency thereof, or Battelle Memorial Institute.
The views and opinions of authors expressed herein do not necessarily state or
reflect those of the United States Government or any agency thereof.

PACIFIC NORTHWEST NATIONAL LABORATORY
operated by
BATTELLE for the UNITED STATES DEPARTMENT OF ENERGY
under Contract DE-AC05-76RL01830
}}}
"""
import os
import sys
import logging

from datetime import timedelta as td, datetime as dt
import uuid
from dateutil.parser import parse

from tcc_ilc.device_handler import ClusterContainer, DeviceClusters, parse_sympy, init_schedule, check_schedule
import pandas as pd
from volttron.platform.agent import utils
from volttron.platform.messaging import topics, headers as headers_mod

from volttron.platform.agent.utils import setup_logging, format_timestamp, get_aware_utc_now
from volttron.platform.agent.math_utils import mean, stdev
from volttron.platform.vip.agent import Agent, Core

from volttron.platform.agent.base_market_agent import MarketAgent
from volttron.platform.agent.base_market_agent.poly_line import PolyLine
from volttron.platform.agent.base_market_agent.point import Point
from volttron.platform.agent.base_market_agent.error_codes import NOT_FORMED, SHORT_OFFERS, BAD_STATE, NO_INTERSECT
from volttron.platform.agent.base_market_agent.buy_sell import BUYER


__version__ = "0.2"

setup_logging()
_log = logging.getLogger(__name__)


class TransactiveIlcCoordinator(MarketAgent):
    def __init__(self, config_path, **kwargs):
        super(TransactiveIlcCoordinator, self).__init__(**kwargs)
        config = utils.load_config(config_path)
        campus = config.get("campus", "")
        building = config.get("building", "")
        logging_topic = config.get("logging_topic", "tnc")
        self.target_topic = '/'.join(['record', 'target_agent', campus, building, 'goal'])
        self.logging_topic = '/'.join([logging_topic, campus, building, "TCILC"])
        cluster_configs = config["clusters"]
        self.clusters = ClusterContainer()

        for cluster_config in cluster_configs:
            device_cluster_config = cluster_config["device_cluster_file"]
            load_type = cluster_config.get("load_type", "discreet")

            if device_cluster_config[0] == "~":
                device_cluster_config = os.path.expanduser(device_cluster_config)

            cluster_config = utils.load_config(device_cluster_config)
            cluster = DeviceClusters(cluster_config, load_type)
            self.clusters.add_curtailment_cluster(cluster)

        self.device_topic_list = []
        self.device_topic_map = {}
        all_devices = self.clusters.get_device_name_list()
        occupancy_schedule = config.get("occupancy_schedule", False)
        self.occupancy_schedule = init_schedule(occupancy_schedule)
        for device_name in all_devices:
            device_topic = topics.DEVICES_VALUE(campus=campus,
                                                building=building,
                                                unit=device_name,
                                                path="",
                                                point="all")

            self.device_topic_list.append(device_topic)
            self.device_topic_map[device_topic] = device_name

        power_token = config["power_meter"]
        power_meter = power_token["device"]
        self.power_point = power_token["point"]
        self.current_time = None
        self.power_meter_topic = topics.DEVICES_VALUE(campus=campus,
                                                      building=building,
                                                      unit=power_meter,
                                                      path="",
                                                      point="all")
        self.demand_limit = None
        self.bldg_power = []
        self.avg_power = 0.
        self.last_demand_update = None
        self.demand_curve = None
        self.power_prices = None
        self.power_min = None
        self.power_max = None

        self.average_building_power_window = td(minutes=config.get("average_building_power_window", 15))
        self.minimum_update_time = td(minutes=config.get("minimum_update_time", 5))
        self.market_name = config.get("market", "electric")
        self.tz = None
        # self.prices = power_prices
        self.oat_predictions = []
        self.comfort_to_dollar = config.get('comfort_to_dollar', 1.0)

        self.prices_from = config.get("prices_from", 'pubsub')
        self.prices_topic = config.get("price_topic", "prices")
        self.prices_file = config.get("price_file")
        self.join_market(self.market_name, BUYER, None, self.offer_callback, None, self.price_callback, self.error_callback)

        # Setup topics for use later
        self.campus = campus
        self.building = building
        topic_tmpl = "{campus}/{building}/{unit}/{point}"
        self.ts_name = "Date"
        self.oat = "OutdoorAirTemperature"
        self.wbp = "WholeBuildingPower"
        oat_point = topic_tmpl.format(campus=self.campus,
                                      building=self.building,
                                      unit=self.unit,
                                      point="OutdoorAirTemperature")
        bldg_power = topic_tmpl.format(campus=self.campus,
                                       building=self.building,
                                       unit=self.unit,
                                       point="WholeBuildingPower")
        self.points = [oat_point, bldg_power]

        # Query baseline data and schedule estimation run
        self.estimate = []
        self.df_baseline = self.query_baseline()
        self.df_Q = self.cal_Q(self.df_baseline)
        self.df_adj = None
        self.schedule_estimate(False)

    def next_scheduled_time(self):
        # Next scheduled time is minute 50 of this hour or next hour
        now = dt.now()
        next_scheduled_time = now.replace(minute=50)
        if now.minute >= 50:
            next_scheduled_time = next_scheduled_time + td(hours=1)
            _log.debug("It's too late. Schedule for next hour.")

        return next_scheduled_time

    def query_data(self, count, timeout=10000):
        df = None
        for point in self.points:
            result = self.vip.rpc.call('platform.historian',
                                       'query',
                                       topic=point,
                                       count=count,
                                       order="LAST_TO_FIRST").get(timeout=timeout)
            df2 = pd.DataFrame(result['values'], columns=[self.ts_name, point])
            df2[self.ts_name] = pd.to_datetime(df2[self.ts_name])
            df2 = df2.resample('H').mean()
            df = df2 if df is None else pd.merge(df, df2, on=self.ts_name, how='outer')

        if df is not None:
            # Convert to local time and do hourly resample
            df[self.ts_name] = pd.to_datetime(df[self.ts_name], utc=True)
            df[self.ts_name] = df[self.ts_name].dt.tz_convert('US/Pacific')
            df[self.ts_name] = df[self.ts_name].dt.tz_localize(None)
            df[self.ts_name] = df[self.ts_name].values.astype('<M8[m]')

        return df

    def query_baseline(self):
        # Get previous event days
        ev_days = self.config.get('event_days', [])
        parsed_ev_days = []
        for ev_day in ev_days:
            try:
                parsed_ev_day = parse(ev_day)
                if parsed_ev_day.tzinfo is None:
                    parsed_ev_day = self.local_tz.localize(parsed_ev_day)
                parsed_ev_days.append(format_timestamp(parsed_ev_day))
            except Exception as e:
                _log.error(e.message)

        # Query baseline data
        df = self.query_data(count=30*24*60, timeout=10000)

        # Filter out non-business and event days
        if df is not None:
            filter = (df[self.ts_name].dt.weekday < 5)
            for day in parsed_ev_days:
                filter |= (df[self.ts_name].dt != day)
            df = df[filter]
        else:
            _log.error("No baseline data.")

        return df

    def query_new_data(self):
        # Query last X hours
        df = self.query_data(count=4*60, timeout=10000)

        # Filter out to get data for last hour
        if df is not None:
            now = dt.now()
            prev = now - td(hours=1)
            start = prev.replace(minute=0, second=0)
            end = now.replace(minute=0, second=0)

            df = df[(df[self.ts_name] >= start) & (df[self.ts_name] < end)]

        return df

    def cal_Q(self, df):
        # Calculate Q_min and Q_max for each record in dataframe
        df_Q = df
        return df_Q

    def estimate(self, df_baseline, df_adj):
        """
        Estimate using hourly profile for last X business day
        """

        # Baseline
        q_min = []
        q_max = []
        for hr in range(0, 24):
            cur_df = df_baseline[df_baseline[self.ts_name].dt.hour == hr]
            q_min.append(cur_df['Qmin'].mean())
            q_max.append(cur_df['Qmax'].mean())

        # Caculate adjustment
        now = dt.now()
        adj_1 = now - td(hours=4)
        adj_2 = now - td(hours=3)
        adj_3 = now - td(hours=2)
        sum_qmin = q_min[adj_1] + q_min[adj_2] + q_min[adj_3]
        sum_qmax = q_max[adj_1] + q_max[adj_2] + q_max[adj_3]
        sum_c_qmin = df_adj['Qmin'].mean()
        sum_c_qmax = df_adj['Qmax'].mean()
        adj_qmin = sum_c_qmin / sum_qmin
        adj_qmax = sum_c_qmax / sum_qmax

        # Apply day-of adjustment
        qmin_est = [x * adj_qmin for x in q_min]
        qmax_est = [x * adj_qmax for x in q_max]


        # Pubhslish the whole qmin and qmax on tnc topic

        return qmin_est, qmax_est

    def schedule_estimate(self, scheduled_call):
        # Query past hours if this is actual scheduled call (ie. not the call when first init())
        if scheduled_call:
            df = self.query_new_data()

            # Estimate Qmin & Qmax for each record
            if df is not None:
                self.df_adj = self.cal_Q(df)
                q_min, q_max = self.estimate(self.df_Q, self.df_adj)
            else:
                _log.error("No adjustment data")

        # Schedule to run every hour (put in onstart later) to update estimate & do adjustment
        next_scheduled_time = self.next_scheduled_time()
        self.core.schedule(next_scheduled_time, self.schedule_estimate, True)

    def setup_prices(self):
        _log.debug("Prices from {}".format(self.prices_from))
        if self.prices_from == "file":
            self.power_prices = pd.read_csv(self.prices_file)
            self.power_prices = self.power_prices.set_index(self.power_prices.columns[0])
            self.power_prices.index = pd.to_datetime(self.power_prices.index)
            self.power_prices.resample('H').mean()
            self.power_prices['MA'] = self.power_prices[::-1].rolling(window=24, min_periods=1).mean()[::-1]
            self.power_prices['STD'] = self.power_prices["price"][::-1].rolling(window=24, min_periods=1).std()[::-1]
            self.power_prices['month'] = self.power_prices.index.month.astype(int)
            self.power_prices['day'] = self.power_prices.index.day.astype(int)
            self.power_prices['hour'] = self.power_prices.index.hour.astype(int)
        elif self.prices_from == "pubsub":
            self.vip.pubsub.subscribe(peer="pubsub", prefix=self.prices_topic, callback=self.update_prices)

    def update_prices(self, peer, sender, bus, topic, headers, message):
        self.power_prices = pd.DataFrame(message)
        self.power_prices = self.power_prices.set_index(self.power_prices.columns[0])
        self.power_prices.index = pd.to_datetime(self.power_prices.index)
        self.power_prices["price"] = self.power_prices
        self.power_prices.resample('H').mean()
        self.power_prices['MA'] = self.power_prices["price"][::-1].rolling(window=24, min_periods=1).mean()[::-1]
        self.power_prices['STD'] = self.power_prices["price"][::-1].rolling(window=24, min_periods=1).std()[::-1]
        self.power_prices['month'] = self.power_prices.index.month.astype(int)
        self.power_prices['day'] = self.power_prices.index.day.astype(int)
        self.power_prices['hour'] = self.power_prices.index.hour.astype(int)

    @Core.receiver("onstart")
    def starting_base(self, sender, **kwargs):
        """
        Startup method:
         - Setup subscriptions to  devices.
         - Setup subscription to building power meter.
        :param sender:
        :param kwargs:
        :return:
        """
        for device_topic in self.device_topic_list:
            _log.debug("Subscribing to " + device_topic)
            self.vip.pubsub.subscribe(peer="pubsub", prefix=device_topic, callback=self.new_data)
        _log.debug("Subscribing to " + self.power_meter_topic)
        self.vip.pubsub.subscribe(peer="pubsub", prefix=self.power_meter_topic, callback=self.load_message_handler)
        self.setup_prices()

    def offer_callback(self, timestamp, market_name, buyer_seller):
        if self.current_time is not None:
            demand_curve = self.create_demand_curve()
            if demand_curve is not None:
                self.make_offer(market_name, buyer_seller, demand_curve)
                topic_suffix = "/".join([self.logging_topic, "DemandCurve"])
                message = {"Curve": demand_curve.tuppleize(), "Commodity": "Electricity"}
                self.publish_record(topic_suffix, message)

    def create_demand_curve(self):
        if self.power_min is not None and self.power_max is not None:
            demand_curve = PolyLine()
            price_min, price_max = self.generate_price_points()
            demand_curve.add(Point(price=price_max, quantity=self.power_min))
            demand_curve.add(Point(price=price_min, quantity=self.power_max))
        else:
            demand_curve = None
        self.demand_curve = demand_curve
        return demand_curve

    def price_callback(self, timestamp, market_name, buyer_seller, price, quantity):
        if self.bldg_power:
            _log.debug("Price is {} at {}".format(price, self.bldg_power[-1][0]))
            dt = self.bldg_power[-1][0]
            occupied = check_schedule(dt, self.occupancy_schedule)

        if self.demand_curve is not None and price is not None and occupied:
            demand_goal = self.demand_curve.x(price)
            self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
        elif not occupied:
            demand_goal = None
            self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
        if price is None:
            price = "None"
        message = {"Price": price, "Quantity": demand_goal, "Commodity": "Electricity"}
        topic_suffix = "/".join([self.logging_topic, "MarketClear"])
        self.publish_record(topic_suffix, message)

    def publish_demand_limit(self, demand_goal, task_id):
        """
        Publish the demand goal determined by clearing price.
        :param demand_goal:
        :param task_id:
        :return:
        """
        _log.debug("Updating demand limit: {}".format(demand_goal))
        self.demand_limit = demand_goal
        if self.last_demand_update is not None:
            if (self.current_time - self.last_demand_update) < self.minimum_update_time:
                _log.debug("Minimum demand update time has not elapsed.")
                return
        if self.current_time is None:
            _log.debug("No data received, not updating demand goal!")
            return

        self.last_demand_update = self.current_time

        start_time = format(self.current_time)
        end_time = format_timestamp(self.current_time.replace(hour=23, minute=59, second=59))
        _log.debug("Publish target: {}".format(demand_goal))
        headers = {'Date': start_time}
        target_msg = [
            {
                "value": {
                    "target": self.demand_limit,
                    "start": start_time,
                    "end": end_time,
                    "id": task_id
                    }
            },
            {
                "value": {"tz": "UTC"}
            }
        ]
        self.vip.pubsub.publish('pubsub', self.target_topic, headers, target_msg).get(timeout=15)

    def new_data(self, peer, sender, bus, topic, headers, message):
        """
        Call back method for device data subscription.
        :param peer:
        :param sender:
        :param bus:
        :param topic:
        :param headers:
        :param message:
        :return:
        """
        _log.info("Data Received for {}".format(topic))
        # topic of form:  devices/campus/building/device
        device_name = self.device_topic_map[topic]
        data = message[0]
        self.current_time = parse(headers["Date"])
        parsed_data = parse_sympy(data)


        parsed_data = [{'OATemp': 72, 'ZoneTem': 73}, {'meta': ''}]
        header = {'Date': '2091-01-01 00:00:00'}
        topic = 'devices/"querytopicfrom database"/all

        self.clusters.get_device(device_name).ingest_data(parsed_data)





    def generate_price_points(self):
        # need to figure out where we are getting the pricing information and the form
        # probably via RPC
        _log.debug("DEBUG_PRICES: {}".format(self.current_time))
        df_query = self.power_prices[(self.power_prices["hour"] == self.current_time.hour) & (self.power_prices["day"] == self.current_time.day) & (self.power_prices["month"] == self.current_time.month)]
        price_min = df_query['MA'] - df_query['STD']*self.comfort_to_dollar
        price_max = df_query['MA'] + df_query['STD']*self.comfort_to_dollar
        _log.debug("DEBUG TCC price - min {} - max {}".format(float(price_min), float(price_max)))
        return max(float(price_min), 0.0), float(price_max)

    def generate_power_points(self, current_power):
        positive_power, negative_power = self.clusters.get_power_bounds()
        _log.debug("DEBUG TCC - pos {} - neg {}".format(positive_power, negative_power))
        return float(current_power + sum(positive_power)), float(current_power - sum(negative_power))

    def load_message_handler(self, peer, sender, bus, topic, headers, message):
        """
        Call back method for building power meter. Calculates the average
        building demand over a configurable time and manages the curtailment
        time and curtailment break times.
        :param peer:
        :param sender:
        :param bus:
        :param topic:
        :param headers:
        :param message:
        :return:
        """
        # Trigger this by using power
        # Use instantaneous power or average building power.
        data = message[0]
        current_power = data[self.power_point]
        current_time = parse(headers["Date"])

        power_max, power_min = self.generate_power_points(current_power)
        _log.debug("QUANTITIES: max {} - min {} - cur {}".format(power_max, power_min, current_power))

        if self.bldg_power:
            current_average_window = self.bldg_power[-1][0] - self.bldg_power[0][0] + td(seconds=15)
        else:
            current_average_window = td(minutes=0)

        if current_average_window >= self.average_building_power_window and current_power > 0:
            self.bldg_power.append((current_time, current_power, power_min, power_max))
            self.bldg_power.pop(0)
        elif current_power > 0:
            self.bldg_power.append((current_time, current_power, power_min, power_max))

        smoothing_constant = 2.0 / (len(self.bldg_power) + 1.0) * 2.0 if self.bldg_power else 1.0
        smoothing_constant = smoothing_constant if smoothing_constant <= 1.0 else 1.0
        power_sort = list(self.bldg_power)
        power_sort.sort(reverse=True)
        avg_power_max = 0.
        avg_power_min = 0.
        avg_power = 0.

        for n in xrange(len(self.bldg_power)):
            avg_power += power_sort[n][1] * smoothing_constant * (1.0 - smoothing_constant) ** n
            avg_power_min += power_sort[n][2] * smoothing_constant * (1.0 - smoothing_constant) ** n
            avg_power_max += power_sort[n][3] * smoothing_constant * (1.0 - smoothing_constant) ** n
        self.avg_power = avg_power
        self.power_min = avg_power_min
        self.power_max = avg_power_max

    def error_callback(self, timestamp, market_name, buyer_seller, error_code, error_message, aux):
        # figure out what to send if the market is not formed or curves don't intersect.
        _log.debug("AUX: {}".format(aux))
        if market_name == "electric":
            if self.bldg_power:
                dt = self.bldg_power[-1][0]
                occupied = check_schedule(dt, self.occupancy_schedule)

            _log.debug("AUX: {}".format(aux))
            if not occupied:
                demand_goal = None
                self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
            else:
                if aux.get('SQn,DQn', 0) == -1 and aux.get('SQx,DQx', 0) == -1:
                    demand_goal = self.demand_curve.min_x()
                    self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
                elif aux.get('SPn,DPn', 0) == 1 and aux.get('SPx,DPx', 0) == 1:
                    demand_goal = self.demand_curve.min_x()
                    self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
                elif aux.get('SPn,DPn', 0) == -1 and aux.get('SPx,DPx', 0) == -1:
                    demand_goal = self.demand_curve.max_x()
                    self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
                else:
                    demand_goal = None
                    self.publish_demand_limit(demand_goal, str(uuid.uuid1()))
        return

    def publish_record(self, topic_suffix, message):
        headers = {headers_mod.DATE: format_timestamp(get_aware_utc_now())}
        message["TimeStamp"] = format_timestamp(self.current_time)
        topic = "/".join([self.record_topic, topic_suffix])
        self.vip.pubsub.publish("pubsub", topic, headers, message).get()


def main(argv=sys.argv):
    """Main method called by the aip."""
    try:
        utils.vip_main(TransactiveIlcCoordinator)
    except Exception as exception:
        _log.exception("unhandled exception")
        _log.error(repr(exception))


if __name__ == "__main__":
    # Entry point for script
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
