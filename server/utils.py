__author__ = 'cristian'

import hashlib

import settings

SALT = b'chat2015'


class DBConnection(object):
    def __init__(self):
        self.con = None

    def __enter__(self):
        self.con = settings.DB_POOL.getconn()
        return self.con, self.con.cursor()

    def __exit__(self, exc_type, exc_val, exc_tb):
        settings.DB_POOL.putconn(self.con)


def get_output_msg(msg, e=None):
    if e is None or not settings.DEBUG:
        return "{0}".format(msg)
    else:
        return "{0}:\n{1}".format(msg, e)


def encrypt_password(text):
    return hashlib.pbkdf2_hmac('sha256', bytes(text, 'utf-8'), SALT, 100000)