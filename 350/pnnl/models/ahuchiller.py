class AhuChiller(object):

    def __init__(self):
        self.tAirReturn = 20.
        self.tAirSupply = 10.
        self.tAirMixed = 20.
        self.cpAir = 1006. # J/kg
        self.c0 = 0 # coefficients are for SEB fan
        self.c1 = 2.652E-01
        self.c2 = -1.874E-02
        self.c3 = 1.448E-02
        self.c4 = 0.
        self.c5 = 0.
        self.pFan = 0.
        self.mDotAir = 0.
        self.staticPressure = 0.
        self.coilLoad = 0.
        self.COP = 6.16
        self.power_unit = 'kW'
        self.name = 'AhuChiller'
        self.oat_predictions = []

        self.has_economizer = True
        self.sat_setpoint = 12.8
        self.economizer_limit = 22.8
        self.tset_avg = 22.8
        self.min_oaf = 0.15
        self.CAV_flag = False
        self.tDis = self.sat_setpoint

    def calcAirFlowRate(self, qLoad):
#        if abs(self.tAirSupply - self.tAirReturn) < 0.5:
#            if qLoad > 0.01:
#                self.mDotAir = abs(qLoad/self.cpAir/(12.88-22.8))
#            else:
#                self.mDotAir = 0
#        else:
#            self.mDotAir = abs(qLoad/self.cpAir/(self.tAirSupply-self.tAirReturn)) # kg/s
         if not self.CAV_flag:
             self.mDotAir = qLoad
         else:
             self.tDis = qLoad
            

    def calcFanPower(self):
        if self.power_unit == 'W':
            self.pFan = (self.c0 + self.c1*self.mDotAir + self.c2*pow(self.mDotAir,2) + self.c3*pow(self.mDotAir,3) + self.c4*self.staticPressure + self.c5*pow(self.staticPressure,2))*1000. # watts
        else:
            self.pFan = (self.c0 + self.c1*self.mDotAir + self.c2*pow(self.mDotAir,2) + self.c3*pow(self.mDotAir,3) + self.c4*self.staticPressure + self.c5*pow(self.staticPressure,2)) # kW

    def calcCoilLoad(self, oat):
        if self.power_unit == 'W':
            temp = 1 # watts
        else:
            temp = 1000.0
        if self.has_economizer:
            if oat < self.tDis:
                coilLoad = 0.0
            elif oat < self.economizer_limit:
                coilLoad = self.mDotAir * self.cpAir * (self.tDis - oat) / temp
            else:
                mat = self.tset_avg*(1.0 - self.min_oaf) + self.min_oaf*oat
                coilLoad = self.mDotAir * self.cpAir * (self.tDis - mat) / temp
        else:
            mat = self.tset_avg * (1.0 - self.min_oaf) + self.min_oaf * oat
            coilLoad = self.mDotAir * self.cpAir * (self.tDis - mat) / temp

        if coilLoad > 0: #heating mode is not yet supported!
            self.coilLoad = 0.0
        else:
            self.coilLoad = coilLoad

    def calcTotalLoad(self, qLoad, oat):
        self.calcAirFlowRate(qLoad)
        return self.calcTotalPower(oat)

    def calcTotalPower(self, oat):
        self.calcFanPower()
        self.calcCoilLoad(oat)
        return abs(self.coilLoad)/self.COP/0.9 + max(self.pFan, 0)