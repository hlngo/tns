import datetime
import time
import pandas as pd

tabs=pd.read_csv('price.csv')
tabsim=pd.read_csv('totalpower.csv')
def convert(u):
   x = time.strptime(u,'%H:%M:%S')
   return datetime.timedelta(hours=x.tm_hour,minutes=x.tm_min,seconds=x.tm_sec).total_seconds()
temp=[]
for i in range(len(tabs['time'])):
      u=tabs['time'].iloc[i].split(',')[0].replace('2018-06-22','')
      temp.append(convert(u))  
tabs['second']=temp
tabs.to_csv('new_price.csv')

temp=[]
for i in range(len(tabsim['date'])):
      u=tabsim['date'].iloc[i].split(',')[0].replace('2018-06-22 ','')
      temp.append(convert(u))  
tabsim['second']=temp
tabsim.to_csv('new_total_price.csv')