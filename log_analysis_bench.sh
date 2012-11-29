#!/bin/bash

#
# Copyright (C) 2011  2ndQuadrant Italia
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#

##
# CONFIGURATION
#
# You can use %infile to placehold the input LOG file,
# and %outfile to placehold the output report file
##

CMD[0]="/usr/bin/pgfouine -file %infile > %outfile 2>/dev/null"
CMD[1]="/usr/bin/pg_query_analyser --input-file=%infile -o %outfile >/dev/null 2>/dev/null"
CMD[2]="/usr/bin/pgbadger -o %outfile %infile  >/dev/null 2>/dev/null"

LOG_FILES="postgres.500MB.log postgres.20MB.log"

##
# END OF CONFIGURATION
##

set -e

declare -i i
declare -i s
i=0
s=0
cmd_n=${#CMD[@]}
DESTDIR=output
rm -rf ${DESTDIR}/*
mkdir -p ${DESTDIR}/{reports,timings,mem}

while [ $i -lt $cmd_n ]
do

    echo "=> Running: ${CMD[$i]}"
    for f in $LOG_FILES
    do
        OUTFILE=${DESTDIR}/reports/${f}.OUT.$i.html
        TIMEFILE=${DESTDIR}/timings/${f}.TIME.$i
        MEMFILE=${DESTDIR}/mem/${f}.MEM.$i
        touch $MEMFILE
        touch $OUTFILE # Needed by pg_query_analyser
        echo "==> on file: ${f} ..."
        CMD_=${CMD[$i]/\%outfile/$OUTFILE}
        CMD_=${CMD_/\%infile/$f}

        /usr/bin/time -f "%e" -o ${TIMEFILE} bash -c "$CMD_" &

        PID=$!
        while true
        do
            if kill -0 $PID 2>/dev/null
            then
                # Ugly
                TREE=$( pstree -p $PID )
                CHILD=${TREE##*\(}
                CHILD=${CHILD%?}
                MEM=$( pmap ${CHILD} | grep total | tr -d ' ' | sed -e 's/K$//' -e 's/^total//' )
                echo "${MEM}" >> $MEMFILE
                sleep 1
            else
                break
            fi
        done
        wait $PID
    done

    i=$i+1
done

##
# Prepare GNUplot data files
##
echo "=> Prepare data file for GNUplot"
for f in $LOG_FILES
do
    i=0
    while [ $i -lt $cmd_n ]
    do
        GP[$i]=$( wc -l ${DESTDIR}/mem/*${f}.MEM.$i )
        i=$i+1
    done
    # Sort array
    readarray -t sorted < <(for a in "${GP[@]}"; do echo "$a"; done | sort -r)
    DATAFILE=${DESTDIR}/mem/total.${f}.data
    n_files=${#sorted[@]}
    touch $DATAFILE
    declare -i n
    n=1
    i=0
    while [ $i -lt $n_files ]
    do
        n=1
        while read line
        do
            if [ $i -eq 0 ]
            then
                echo "$n,$line" >> $DATAFILE
            else
                CURLINE=$( sed "${n}q;d" $DATAFILE )
                sed -i -e "${n}s/${CURLINE}/${CURLINE},${line}/" $DATAFILE
            fi
            n=$n+1
        done < ${sorted[$i]#*\ }
        i=$i+1
    done
done

##
# Prepare GNUplot configuration files
##
echo "=> Prepare GNUplot configuration file"
for f in $LOG_FILES
do
    i=0
    while [ $i -lt $cmd_n ]
    do
        PLOT_CMD="${PLOT_CMD} '${DESTDIR}/mem/total.${f}.data' using 1:(\$$( expr $i + 2 )/1024) with lines ti '${CMD[$i]}' "
        if [ $i -ne $( expr $cmd_n - 1) ]
        then
            PLOT_CMD="${PLOT_CMD}, "
        fi
        i=$i+1
    done

    GPCONF=${DESTDIR}/mem/gnuplot.${f}.conf
    PNG=${DESTDIR}/mem/plot.${f}.png
    cat > $GPCONF << EOF
set terminal pngcairo
set output "$PNG"
set terminal png size 1024, 768

set title "Analisi LOG file ~500MB" font "DroidSerif,20"
set xlabel "Time (s)" offset 0.0,0.0
set ylabel "Mem (MB)" offset 1.0,0.0
set grid
set border 3
set size 1,1
set datafile separator ","
set key vert below

plot ${PLOT_CMD}
EOF
    echo "==> GNUplot configuration file: ${GPCONF}"
done

exit 0
