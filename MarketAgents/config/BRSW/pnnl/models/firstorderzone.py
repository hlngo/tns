class FirstOrderZone(object):
    
    def __init__(self):
        self.c1 = []
        self.c2 = []
        self.c3 = []
        self.name = "FirstOrderZone"

    def getQ(self, oat, temp, temp_stpt, index):
        Q = (oat-temp)/self.r[index]-self.c[index]*(temp_stpt-temp)/(1/60.)+self.w[index]
        return Q

    def getT(self, oat, temp, temp_stpt, index):
        T = (oat-temp_stpt)*self.c1[index]+self.c2[index]*(temp-temp_stpt)+self.c3[index]
        return T

    def getM(self, oat, temp, temp_stpt, index):
        M = (oat-temp_stpt)*self.c1[index]+self.c2[index]*(temp-temp_stpt)+self.c3[index]
        return M