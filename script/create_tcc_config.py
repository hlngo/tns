import socket
import time
import numpy as np
import sys
import random as rd
import json,collections
import pandas as pd

def writeVariableFile(config):
    vavs={}
    lights={}
    i=1
    j=1
    with open(config) as f:
        config=json.load(f,object_pairs_hook=collections.OrderedDict)
        if 'inputs' in config: 
            INPUTS = config['inputs']
        if 'outputs' in config:
            OUTPUTS = config['outputs']
        for obj in INPUTS.itervalues():

               temp={}
               if obj['field'].find('ZoneCoolingTemperatureSetPoint')!=-1:
                         vavs[str(i)]=obj['name'].replace('_CLGSETP_SCH','')
                         i=i+1
#                         print obj['name']
                         filename=obj['name'].replace('_SCH','.config')
#                         print filename
                         temp['agent_name']='lb1_'+obj['name'].replace('_CLGSETP_SCH','')
                         temp['setpoint']='ZoneCoolingTemperatureSetPoint'
                         temp['heartbeat_period']=300.0, 
                         temp['parent_device_points']={}
                         temp['parent_device_points']['supply_fan_status']='SupplyFanStatus'
                         temp['parent_device_points']['outdoor_air_temperature']='OutdoorAirTemperature'
                         temp['price_multiplier']=2.0,
                         temp['device_points']={}
                         temp['device_points']['zone_dat']='ZoneDischargeAirTemperature'
                         temp['device_points']['zone_airflow']='ZoneAirFlow'                         
                         temp['device_points']['zone_temperature']='ZoneTemperature' 

                         temp['campus']=obj['topic'].split('/')[0]
                         temp['building']=obj['topic'].split('/')[1]
                         temp['parent_device']=obj['topic'].split('/')[2]
                         temp['device']=obj['topic'].split('/')[3]
                         
                         temp['tMax']=obj['default']+1
                         temp['tMin']=obj['default']-1                         
                         temp['tIn']=obj['default']
                         temp['market_name']='air'+temp['parent_device'][-1]

               else:
                         lights[str(j)]=obj['name'].replace('_BLDG_LIGHT_SCH','')
                         j=j+1
                         temp['lighting_level_stpt']='DimmingLevelOutput'
                         filename=obj['name'].replace('_SCH','.config')
#                         print obj['topic']
                         temp['campus']=obj['topic'].split('/')[0]
                         temp['building']=obj['topic'].split('/')[1]
                         temp['device']=obj['topic'].split('/')[2]
                         temp['path']=obj['topic'].split('/')[3]
                         temp['schedule_device']='AHU1'
                         temp['schedule_point']='SupplyFanStatus'
                         temp['market_name']='electric'
                         temp['agent_name']='lb1_'+obj['name'].replace('_SCH','')						 
                         temp['heartbeat_period']=300.0,
                         temp['price_multiplier']=2.0,
                         temp['default_dimming_level']=100.0,
                         temp['min_occupied_lighting_level']=70.0,
                         
               with open('config/'+filename, 'w') as fp:
                         json.dump(temp, fp, indent=4)
        with open('vavs', 'w') as fp:
                         json.dump(vavs, fp, indent=4)
        with open('lights', 'w') as fp:
                         json.dump(lights, fp, indent=4)
writeVariableFile('ep_LargeOffice.config')