#!/bin/bash
su -l eq -c 'cd /home/eq/www && export MOJO_MODE=development && carton exec -- hypnotoad -s script/eq && sleep 1 && carton exec hypnotoad script/eq'
