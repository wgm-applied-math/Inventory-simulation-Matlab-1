#!/bin/bash

# This is a script I use to join files produced by publish_as_pdfs.m into one printout.
# You generally won't need to use it.

cd 'html'

pdfjam -o 'Inventory-simulation-printout.pdf' \
       Inventory.pdf \
       OrderReceived.pdf \
       Event.pdf \
       ShipmentArrival.pdf \
       BeginDay.pdf \
       EndDay.pdf \
       test_Inventory.pdf \
       run_Inventory.pdf
