#!/usr/bin/env python

""" uses the SmartCardSSH class to add/remove pkcs11 devices from ssh-agent """

import argparse
from getpass import getpass

from sc_ssh.sc_ssh import SmartCardSSH


def parseargs():
    """ Simple function to parse args """

    args = None
    parser = argparse.ArgumentParser(description="Script to load and unload a pkcs11 token",
                                     formatter_class=argparse.RawTextHelpFormatter
    )

    parser.add_argument('-l',
                        action='store',
                        dest='pkcs11_path',
                        default='/usr/local/lib/opensc-pkcs11.so',
                        help='path to pkcs11.so file.\n'
                             '  (default: %(default)s)')
                        
    subcommand_parser = parser.add_subparsers(dest='subcommand')

    add_parser = subcommand_parser.add_parser('add',
                                       help='Add smartcard to ssh-agent')
    del_parser = subcommand_parser.add_parser('del',
                                       help='Remove smartcard from ssh-agent')

    args = parser.parse_args()
    return args


def main():
    """ Our main function to perform actions based on supplied args """

    args = parseargs()
    smart_card = SmartCardSSH(args.pkcs11_path)

    if args.subcommand == 'del':
        smart_card.remove_key()
    else:
        pin = getpass('PIN: ')
        smart_card.add_key(pin)


if __name__ == '__main__':
    main()
