import logging

from volttron.pnnl.transactive_base.transactive.transactive import TransactiveBase
from volttron.platform.agent.base_market_agent.poly_line import PolyLine
from volttron.platform.agent.base_market_agent.point import Point
from volttron.platform.agent.base_market_agent.buy_sell import BUYER, SELLER
from volttron.platform.agent.utils import setup_logging

_log = logging.getLogger(__name__)
setup_logging()
__version__ = '0.3'


class Aggregator(TransactiveBase):
    def __init__(self, config, **kwargs):
        super(Aggregator, self).__init__(config, **kwargs)
        self.supplier_market_base_name = config.get("supplier_market_name", None)
        self.consumer_market_base_name = config.get("consumer_market_name", None)
        self.consumer_market = []
        self.supplier_market = []
        self.supply_commodity = None
        self.consumer_commodity = self.commodity
        self.aggregate_demand = []
        self.translated_demand = []
        for i in range(self.market_number):
            if self.supplier_market_base_name is not None:
                self.supplier_market.append('_'.join([self.supplier_market_base_name, str(i)]))
            if self.consumer_market_base_name is not None:
                self.consumer_market.append('_'.join([self.consumer_market_base_name, str(i)]))
            self.translated_demand.append(None)
            self.aggregate_demand.append(None)

    def init_markets(self):
        for market in self.supplier_market:
            self.join_market(market, SELLER, None, None,
                             self.aggregate_callback, self.supplier_price_callback, self.error_callback)
        for market in self.consumer_market:
            self.join_market(market, BUYER, None, None,
                             None, self.consumer_price_callback, self.error_callback)

    def aggregate_callback(self, timestamp, market_name, buyer_seller, agg_demand):
        if buyer_seller == BUYER:
            market_index = self.supplier_market.index(market_name)
            _log.debug("{} - received aggregated {} curve - {}".format(self.agent_name, market_name, agg_demand.points))
            self.aggregate_demand[market_index] = agg_demand
            self.translated_demand[market_index] = self.translate_aggregate_demand(agg_demand, market_index)
            if self.consumer_market:
                success, message = self.make_offer(self.consumer_market[market_index], BUYER, self.translated_demand[market_index])
            elif self.supplier_market:
                success, message = self.make_offer(self.supplier_market[market_index], SELLER, self.translated_demand[market_index])
            else:
                _log.warn("{} - No markets to submit supply curve!".format(self.agent_name))
                success = False
            if success:
                _log.debug("{}: make a offer for {}".format(self.agent_name, market_name))
            else:
                _log.debug("{}: offer for the {} was rejected".format(self.agent_name, market_name))
            topic_suffix = "/".join([self.agent_name, "DemandCurve"])
            message = {"MarketIndex": market_index, "Curve": self.translated_demand[market_index].tuppleize(), "Commodity": self.consumer_commodity}
            _log.debug("{} debug demand_curve - curve: {}".format(self.agent_name, self.translated_demand[market_index].points))
            self.publish_record(topic_suffix, message)
            #    prices = self.determine_prices()
            #     supply_curve = PolyLine()
            #     supply_curve.add(Point(price=prices[0], quantity=0.0))
            #     supply_curve.add(Point(price=prices[-1], quantity=0.001))
            #     success, message = self.make_offer(market_name, SELLER, supply_curve)

    def consumer_price_callback(self, timestamp, consumer_market, buyer_seller, price, quantity):
        self.report_cleared_price(buyer_seller, consumer_market, price, quantity, timestamp)
        market_index = self.consumer_market.index(consumer_market)
        supply_market = consumer_market.replace(self.consumer_market_base_name, self.supplier_market_base_name)
        if price is not None:
            self.make_supply_offer(price, supply_market)
            _log.debug("{}: making offer on air market".format(self.agent_name))
        if self.translated_demand[market_index] is not None and self.translated_demand[market_index].points:
            cleared_quantity = self.translated_demand[market_index].x(price)
        _log.debug("{} price callback market: {}, price: {}, quantity: {}".format(self.agent_name, consumer_market, price, quantity))
        topic_suffix = "/".join([self.agent_name, "MarketClear"])
        message = {"MarketIndex": market_index, "Price": price, "Quantity": [quantity, cleared_quantity], "Commodity": self.commodity}
        self.publish_record(topic_suffix, message)
        # else:
        #     supply_curve = PolyLine()
        #     prices = self.deterine_prices()
        #     supply_curve.add(Point(price=prices[0], quantity=0.1))
        #     supply_curve.add(Point(price=prices[-1], quantity=0.1))
        #     success, message = self.make_offer(air_market_name, SELLER, supply_curve)

    def create_supply_curve(self, clear_price, supply_market):
        _log.debug("{}: clear consumer market price {}".format(self.agent_name, clear_price))
        index = self.supplier_market.index(supply_market)
        supply_curve = PolyLine()
        min_quantity = self.aggregate_demand[index].min_x()*0.8
        max_quantity = self.aggregate_demand[index].max_x()*1.2
        supply_curve.add(Point(price=clear_price, quantity=min_quantity))
        supply_curve.add(Point(price=clear_price, quantity=max_quantity))
        return supply_curve

    def supplier_price_callback(self, timestamp, market_name, buyer_seller, price, quantity):
        self.report_cleared_price(buyer_seller, market_name, price, quantity, timestamp)

    def make_supply_offer(self, price, supply_market):
        supply_curve = self.create_supply_curve(price, supply_market)
        success, message = self.make_offer(supply_market, SELLER, supply_curve)
        if success:
            _log.debug("{}: make offer for Market: {} {} Curve: {}".format(self.agent_name,
                                                                           supply_market,
                                                                           SELLER,
                                                                           supply_curve.points))
        market_index = self.supplier_market.index(supply_market)
        topic_suffix = "/".join([self.agent_name, "SupplyCurve"])
        message = {"MarketIndex": market_index, "Curve": supply_curve.tuppleize(), "Commodity": self.supply_commodity}
        _log.debug("{} debug demand_curve - curve: {}".format(self.agent_name, supply_curve.points))
        self.publish_record(topic_suffix, message)

    def report_cleared_price(self, buyer_seller, market_name, price, quantity, timestamp):
        _log.debug("{}: ts - {}, Market - {} as {}, Price - {} Quantity - {}".format(self.agent_name,
                                                                                     timestamp,
                                                                                     market_name,
                                                                                     buyer_seller,
                                                                                     price,
                                                                                     quantity))

    def offer_callback(self, timestamp, market_name, buyer_seller):
        pass
