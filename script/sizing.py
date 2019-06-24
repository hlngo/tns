import json,collections
import pandas as pd

f=open('eplusout.eio','r')
lines=f.readlines()
f.close()


with open('vavs') as f:
        config=json.load(f,object_pairs_hook=collections.OrderedDict)

vavs=[]
for i in range(1,len(config)+1):
     vavs.append(config[str(i)])

occupancy_sch='HVACOPERATIONSCHD:Schedule Value [](TimeStep)'

light_sch='BLDG_LIGHT_SCH:Schedule Value [](TimeStep)'

tab=pd.read_csv('eplusout.csv')
tab=tab.iloc[::60, :]
x=tab[occupancy_sch].values
y=tab[light_sch].values

print x


for vav in vavs:
     print vav
     for line in lines:
           if line.lower().find(vav.lower()+' vav box component')!=-1 and line.find('Design Size Maximum Air Flow Rate [m3/s]')!=-1:
                   airflow=float(line.split(',')[-1])
                   with open('config/'+vav+'_CLGSETP.config') as f:
                         config=json.load(f,object_pairs_hook=collections.OrderedDict)
                         config['mDotMax']=airflow
                         config['mDotMin']=airflow*0.3
                         config['hvac_occupancy_schedule']=list(x)
                   with open('config/'+vav+'_CLGSETP.config', 'w') as fp:
                         json.dump(config, fp, indent=4)
           if line.lower().find(vav.lower()+'_lights')!=-1:
                   light_level=float(line.split(',')[6])
                   with open('config/'+vav+'_BLDG_LIGHT.config') as f:
                         config=json.load(f,object_pairs_hook=collections.OrderedDict)
                         config['Pabsnom']=light_level/100
                         config['occupancy_schedule']=list(x)
                         config['lighting_default_setpoint']=list(y)
                   with open('config/'+vav+'_BLDG_LIGHT.config', 'w') as fp:
                         json.dump(config, fp, indent=4)                   