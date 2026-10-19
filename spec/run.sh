#!/bin/sh
# Runs the specs with coverage and fails unless every line in LeanPad/ is covered.
set -e
rm -f luacov.stats.out luacov.report.out
busted
luacov
sed -n '/^Summary/,$p' luacov.report.out
total=$(awk '$1 == "Total" { print $NF }' luacov.report.out)
if [ "$total" != "100.00%" ]; then
	echo "Coverage is $total, expected 100.00%. Missed lines are marked ****0 in luacov.report.out."
	exit 1
fi
