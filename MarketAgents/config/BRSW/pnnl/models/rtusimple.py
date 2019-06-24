class FirstOrderZone(object):

    def __init__(self):
        self.c1 = []
        self.c2 = []
        self.c3 = []
        self.c = 0
        self.name = "FirstOrderZone"

    def getT(self, tpre, oat, on, index):
        T = tpre + (oat-tpre)*self.c1[index]-self.c*on*self.c2[index]+self.c3[index]
        return T
