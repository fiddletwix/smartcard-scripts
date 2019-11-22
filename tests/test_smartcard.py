#!/usr/bin/env python

from unittest import TestCase
from unittest.mock import patch, call
from paramiko.py3compat import byte_chr
from sc_ssh.sc_ssh import *

class TestSmartCard(TestCase):

    @patch('sc_ssh.sc_ssh.Agent')
    def test_smart_card(self, mock_agent):

        agent = mock_agent.return_value
        agent._send_message.return_value = (SSH_AGENT_SUCCESS, byte_chr(SSH_AGENT_SUCCESS))

        sc = SmartCardSSH()
        result = sc._smart_card(SSH_AGENTC_ADD_SMARTCARD_KEY, '123456')
        self.assertEqual(result, SSH_AGENT_SUCCESS)

    @patch('sc_ssh.sc_ssh.Agent')
    def test_addkey(self, mock_agent):

        agent = mock_agent.return_value
        agent._send_message.return_value = (SSH_AGENT_SUCCESS, byte_chr(SSH_AGENT_SUCCESS))

        sc = SmartCardSSH()
        self.assertIsNone(sc.add_key('123456', True, False))

    @patch('sc_ssh.sc_ssh.Agent')
    def test_removekey(self, mock_agent):

        agent = mock_agent.return_value
        agent._send_message.return_value = (SSH_AGENT_SUCCESS, byte_chr(SSH_AGENT_SUCCESS))

        sc = SmartCardSSH()
        self.assertIsNone(sc.remove_key(False))
