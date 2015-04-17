__author__ = 'cristian'

from psycopg2 import pool

DEBUG = True

DB_NAME = 'chat'
DB_USER = 'root'
DB_PASSW = 'toor'
DB_POOL = pool.ThreadedConnectionPool(1,
                                      2,
                                      database=DB_NAME,
                                      user=DB_USER,
                                      password=DB_PASSW)
