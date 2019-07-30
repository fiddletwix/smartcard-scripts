#!/usr/bin/env python

import argparse
from getpass import getpass

from sc_ssh.sc_ssh import SmartCardSSH

def parseargs():
    """ Simple function to parse args """
    
    args = None
    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers(dest='subcommand')
    add_parser = subparsers.add_parser('add',
                                       help='Add smartcard to ssh-agent')
    del_parser = subparsers.add_parser('del',
                                       help='Remove smartcard from ssh-agent')
    
    args = parser.parse_args()
    return args


def main():
    """ Our main function to perform actions based on supplied args """

    args = parseargs()
    sc = SmartCardSSH()

    if args.subcommand == 'del':
        sc.remove_key()
    else:
        pin = getpass('PIN: ')
        sc.add_key(pin)
        

if __name__ == '__main__':
    main()
