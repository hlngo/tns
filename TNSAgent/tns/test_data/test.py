from point import Point


class TestEplus:
    def __init__(self):
        self.ep_lines = []
        self.cur_ep_line = 0
        ep_res_path = '/Users/ngoh511/Documents/projects/PycharmProjects/transactivenetwork/TNSAgent/tns/test_data/energyplus.txt'
        with open(ep_res_path, 'r') as fh:
            for line in fh:
                self.ep_lines.append(line)

    def sim(self):
        self.quantities = []
        self.prices = []
        self.building_demand_curves = []

        if self.cur_ep_line < len(self.ep_lines):
            for i in range(self.cur_ep_line, len(self.ep_lines)):
                line = self.ep_lines[i]
                if "mixmarket DEBUG: Quantities: " in line:
                    self.quantities = eval(line[line.find('['):])
                if "mixmarket DEBUG: Prices: " in line:
                    self.prices = eval(line[line.find('['):])
                if "mixmarket DEBUG: Curves: " in line:
                    tmp = eval(line[line.find('['):])

                    for item in tmp:
                        if item is None:
                            self.building_demand_curves.append(item)
                        else:
                            p1 = Point(item[0][0], item[0][1])
                            p2 = Point(item[1][0], item[1][1])
                            self.building_demand_curves.append((p1, p2))

                # Stop when have enough information (ie. all data responded by a single E+ simulation)
                if len(self.quantities)>0 and len(self.prices)>0 and len(self.building_demand_curves)>0:
                    self.cur_ep_line = i+1
                    break

            self.elastive_load_model.set_tcc_curves(self.quantities,
                                                    self.prices,
                                                    self.building_demand_curves)
            self.balance_market(1)


if __name__ == '__main__':
    ep = TestEplus()
    ep.sim()

    print(ep.ep_lines)
