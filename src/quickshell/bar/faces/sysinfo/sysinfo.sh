#!/usr/bin/env bash
read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
sleep 0.5
read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
t1=$((u1+n1+s1+i1+w1+q1+sq1+st1)); t2=$((u2+n2+s2+i2+w2+q2+sq2+st2))
dt=$((t2-t1)); di=$(( (i2+w2)-(i1+w1) ))
cpu=0; [ "$dt" -gt 0 ] && cpu=$(( (100*(dt-di))/dt ))

ram=$(free -m | awk '/Mem:/{printf "%.1f %d", $3/1024, $3*100/$2}')

t=""
for h in /sys/class/hwmon/hwmon*; do
  case "$(cat "$h/name" 2>/dev/null)" in
    k10temp|coretemp) t=$(cat "$h/temp1_input" 2>/dev/null); break;;
  esac
done
[ -z "$t" ] && t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
temp=0; [ -n "$t" ] && temp=$((t/1000))

echo "$cpu $ram $temp"
