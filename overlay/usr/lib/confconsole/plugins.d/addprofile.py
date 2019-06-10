''' Create a link to a profile created with openvpn-addclient '''

import os, glob
from subprocess import check_output, CalledProcessError, PIPE
TITLE = "Create profile download page"

def run():
    list = glob.glob("/etc/openvpn/easy-rsa/keys/*.ovpn")
    profiles = []
    for idx, file in enumerate(list):    
        base = os.path.basename(file)
        file = os.path.splitext(base)[0]
        profiles.append((file, str(idx)))
    
    if profiles:
        ret, profile = console.menu(TITLE, "Select profile", profiles) 
        if ret == 0:
            console.msgbox(TITLE, check_output(["/var/www/openvpn/bin/addprofile", profile]))

    if not profiles:
        console.msgbox(TITLE, "First create a profile with Addclient plugin")
  

