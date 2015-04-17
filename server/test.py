__author__ = 'cristian'

import json
import unittest

import requests

HOST = 'http://127.0.0.1'
PORT = 8000


class TestServer(unittest.TestCase):
    def __init__(self, arg):
        super(TestServer, self).__init__(arg)
        self.url = "{0}:{1}".format(HOST, PORT)
        url = self.get_url("/Test/Init/")
        r = requests.post(url)
        self.assertEqual(r.text, "OK")

    def get_url(self, path):
        return "{0}{1}".format(self.url, path)

    def test_server_running(self):
        url = self.get_url("/")
        r = requests.get(url)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.text, "It's running")

    def test_user_00_creation(self):
        url = self.get_url("/Users/Create/")
        user = {
            "full_name": "Cristian David Velázquez Ramírez",
            "username": "cdvr1993",
            "password": "cdvr1993"
        }
        data = json.dumps(user)
        r = requests.post(url, data)
        self.assertEqual(r.text, "OK")

    def test_user_01_list(self):
        path = "/Users/List/"
        url = self.get_url("/Users/List/")
        data = {"filter": "cdvr"}
        r = requests.get(url, params=data)
        self.assertRegex(r.text, data['filter'])

    def test_user_02_deletion(self):
        path = "/Users/Delete/"
        url = self.get_url(path)
        data = json.dumps({"username": "cdvr1993"})
        r = requests.post(url, data)
        self.assertEqual(r.text, "OK")


if __name__ == '__main__':
    unittest.main()