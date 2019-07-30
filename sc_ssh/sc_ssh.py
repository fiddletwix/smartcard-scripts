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

class SmartCardSSH(object):


    
    def __init__(self, pkcs11_file='/usr/local/lib/opensc-pkcs11.so'):
        self._PKCS11_SO = pkcs11_file
        return

    def remove_key(self, show_results=True):
        result = self._smart_card(SSH_AGENTC_REMOVE_SMARTCARD_KEY)
        if show_results:
            print("Removing smartcard")
            self.display_results(result) 

    def add_key(self, pin, remove_first=True):
        self.remove_key(show_results=False)
        print("Adding smartcard")
        result = self._smart_card(SSH_AGENTC_ADD_SMARTCARD_KEY, pin)
        self.display_results(result)

    def display_results(self, ret_val):
        result_output = OKAY if ret_val == SSH_AGENT_SUCCESS else FAIL
        print('\033[A\033[70G {}'.format(result_output))
        
    def _smart_card(self, agent_request, pin=''):
        """ Performs ssh-agent actions on smart cards using paramiko """
        
        agent = Agent()
        msg = Message()
        msg.add_byte(agent_request) 
        msg.add_string(self._PKCS11_SO)
        msg.add_string(pin)
        
        ptype, result = agent._send_message(msg)
        return ptype
    
