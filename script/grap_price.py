import os
files=os.listdir(".")
logfiles=[]
for file in files:
    if file.lower().find('.log')!=-1 and file.lower().find('.csv')==-1:
          logfiles.append(file)
import re
import pandas as pd
tabs=pd.DataFrame()
timeindex=[]
point1=[]
for logfile in logfiles:
      print logfile
      f=open(logfile,'r')
      lines=f.readlines()
      f.close()
      for line in lines:

          if line.find('Clearing mixmarket: electric_0 Price')!=-1 and logfile.find('2018-06-22')!=-1:

                                 temp= line.split()
                                 temp1=temp[0].replace('[','')+temp[1]
                                 point1.append(temp[10])
                                 timeindex.append(temp1)  
print len(timeindex)
print len(point1)
tabs['time']=timeindex
tabs['point1']=point1
print tabs
tabs.to_csv('price.csv')