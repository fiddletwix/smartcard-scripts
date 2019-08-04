# pylint: disable=W0212

"""  Class, functions and variables used to add pkcs11 devices to ssh-agent """
from paramiko.agent import Agent
from paramiko.agent import Message
from paramiko.py3compat import byte_chr

# Pulled from OpenSSH's authfd.h file
SSH_AGENT_FAILURE = 5
SSH_AGENT_SUCCESS = 6

SSH_AGENTC_ADD_SMARTCARD_KEY = byte_chr(20)
SSH_AGENTC_REMOVE_SMARTCARD_KEY = byte_chr(21)

# Ansi color codes
OKAY = '\033[92m[ OKAY ]\033[0m'
FAIL = '\033[91m[ FAIL ]\033[0m'


def display_results(ret_val):
    """ Displays ANSI colored output to indicate success or failure """

    result_output = OKAY if ret_val == SSH_AGENT_SUCCESS else FAIL
    print('\033[A\033[70G {}'.format(result_output))


class SmartCardSSH():
    """ class for adding and removing pkcs11 devices to ssh agents """

    def __init__(self, pkcs11_file='/usr/local/lib/opensc-pkcs11.so'):
        self._pkcs11_so = pkcs11_file

    def remove_key(self, show_results=True):
        """ Remove pkcs11 device from ssh-agent """

        result = self._smart_card(SSH_AGENTC_REMOVE_SMARTCARD_KEY)
        if show_results:
            print("Removing smartcard")
            display_results(result)

    def add_key(self, pin, remove_first=True, show_results=True):
        """
        Add pkcs11 device from ssh-agent with an option(default True) to
        remove any existing pkcs11 device from the ssh-agent before attempting
        to add it.
        """

        if remove_first:
            self.remove_key(show_results=False)
        result = self._smart_card(SSH_AGENTC_ADD_SMARTCARD_KEY, pin)
        if show_results:
            print("Adding smartcard")
            display_results(result)

    def _smart_card(self, agent_request, pin=''):
        """ Performs ssh-agent actions on smart cards using paramiko """

        agent = Agent()
        msg = Message()
        msg.add_byte(agent_request)
        msg.add_string(self._pkcs11_so)
        msg.add_string(pin)
        return (agent._send_message(msg))[0]
