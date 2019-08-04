# Yubikey SSH Tools

## What

This is a collection of python code and scripts help configure the PIV application running on a Yubikey for use as ssh private key.


## Why

There is already a [guide](https://developers.yubico.com/PIV/Guides/SSH_with_PIV_and_PKCS11.html) out there for configuring the PIV tool and using it as a ssh private key.  These scripts and modules try to simplify the process.

## How to Use

ykutil.sh is a shell script to setup a PIN and initialize a certificate for use with the PIV personality of a yubikey.

```
 $ ykutil.sh --help
usage: ./ykutil.sh [OPTIONS] COMMAND [SUBCOMMANDS]

This script will help setup a yubikey as well as extract information from it.

OPTIONS:
    -d             Enables debug mode
    -l             Specifies a log file. Note: This logfile will contain
                   sensitive information and needs to handled with care.
COMMANDS:
    reset          Resets the yubikey. THIS DESTROYS ALL PIV DATA
    setup          Resets the yubikey and configures a new PIV certificate
    change-pin     changes pin
    show           Displays information about the yubikey
```

scadd.py is a script to load and unload a smartcard into your ssh-agent.

```
$ ./scadd.py --help
usage: scadd.py [-h] [-l PKCS11_PATH] {add,del} ...

Script to load and unload a pkcs11 token

positional arguments:
  {add,del}
    add           Add smartcard to ssh-agent
    del           Remove smartcard from ssh-agent

optional arguments:
  -h, --help      show this help message and exit
  -l PKCS11_PATH  path to pkcs11.so file.
                    (default: /usr/local/lib/opensc-pkcs11.so)
```