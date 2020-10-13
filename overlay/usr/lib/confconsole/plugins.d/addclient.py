''' Helper script for openvpn-addclient '''

import os
from subprocess import Popen, CalledProcessError, PIPE, check_output

TITLE = "Add client"

def run():
    while True:
        rty, name = console.inputbox(TITLE, "Enter name")
        if rty == 'cancel': break

        rte, email = console.inputbox(TITLE, "Enter email")

        if rte == 'ok' and rty == 'ok':
            proc = Popen(["openvpn-addclient", name, email], stderr=PIPE)
            _, out = proc.communicate()
            returncode = proc.returncode
            if returncode == 0:
                console.msgbox(TITLE, check_output(["/var/www/openvpn/bin/addprofile", name], text=True)) 
            elif returncode == 1:
                        console.msgbox(TITLE, '{} ({})'.format(out, name))
            break
        else:
           break
