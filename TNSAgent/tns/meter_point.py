# -*- coding: utf-8 -*- {{{
# vim: set fenc=utf-8 ft=python sw=4 ts=4 sts=4 et:

# Copyright (c) 2017, Battelle Memorial Institute
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# 'AS IS' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation
# are those of the authors and should not be interpreted as representing
# official policies, either expressed or implied, of the FreeBSD
# Project.
#
# This material was prepared as an account of work sponsored by an
# agency of the United States Government.  Neither the United States
# Government nor the United States Department of Energy, nor Battelle,
# nor any of their employees, nor any jurisdiction or organization that
# has cooperated in the development of these materials, makes any
# warranty, express or implied, or assumes any legal liability or
# responsibility for the accuracy, completeness, or usefulness or any
# information, apparatus, product, software, or process disclosed, or
# represents that its use would not infringe privately owned rights.
#
# Reference herein to any specific commercial product, process, or
# service by trade name, trademark, manufacturer, or otherwise does not
# necessarily constitute or imply its endorsement, recommendation, or
# favoring by the United States Government or any agency thereof, or
# Battelle Memorial Institute. The views and opinions of authors
# expressed herein do not necessarily state or reflect those of the
# United States Government or any agency thereof.
#
# PACIFIC NORTHWEST NATIONAL LABORATORY
# operated by BATTELLE for the UNITED STATES DEPARTMENT OF ENERGY
# under Contract DE-AC05-76RL01830

# }}}


# A MeterPoint may correlate directly with a meter. It necessarily
# corresponds to one measurement type (see MeasurementType enumeration) and
# measurement location within the circuit. Therefore, a single physical
# meter might be the source of more than one MeterPoint.

from datetime import datetime, date, timedelta

from measurement_type import MeasurementType
from measurement_unit import MeasurementUnit
from helpers import format_ts, format_date


class MeterPoint:
    # Text name that identifies a data file, database, or historian
    # where meter data points are to be stored. A default is provided,
    # but a meaningful filename should be used.
    today = date.today()
    dateFile = 'MP' + format_date(today)

    # DESCRIPTION
    description = ''

    # The measurement point datum that was collected during the last
    # reading update. This measurement must be of the measurement type
    # and measurement unit specified by object properties. The
    # measurement took place at the last update datetime. If needed
    # these measurements should be saved to a database or historian.
    lastMeasurement = None  # (1, 1)

    # Datetime of the last meter reading. This time is used with
    # the measurement interval to determine when the meter should be
    # read.
    lastUpdate = datetime.utcnow()

    # Constant time interval between readings. This and the last
    # measurement time are used to schedule the next meter reading.
    measurementInterval = timedelta(hours=1)

    # See MeasurementType enumeration. Property being metered.
    measurementType = MeasurementType.Unknown

    # See MeasurementUnit enumeration. Allowed units of measure. This
    # formulation is currently simplified by allowing only a limited
    # number of measurement units. These are not necessarily the raw
    # units; it should be the proper converted units.
    measurementUnit = MeasurementUnit.Unknown

    # NAME
    name = ''

    def __init__(self):
        pass

    def read_meter(self, obj):
        # Read the meter point at scheduled intervals
        #
        # MeterPoints are updated on a schedule. Properties have been defined to
        # keep track of the time of the last update and the interval between
        # updates.
        #
        # While this seems easy, meters will be found to be diverse and may use
        # diverse standards and protocols. Create subclasses and redefine this
        # function as needed to handle unique conditions.
        print('Made it to MeterPoint.read_meter() for ' + obj.name)

    def store(self):
        """
        Store last measurement into historian
        The default approach here could be to append a text record file. If the
        file is reserved for one meterpoint, little or no metadata need be
        repeated in records. Minimum content should be reading time and datum.
        Implementers will be found to have diverse practices for historians.
        """
        print('Made it to store() function in ' + self.name + ' targeting database ' + self.dataFile)

        # Open a simple text file for appending
        # Append the formatted, paired last measurement time and its datum
        with open(self.dataFile, "a") as myfile:
            myfile.write("{},{};".format(format_ts(self.lastUpdate), self.lastMeasurement))
