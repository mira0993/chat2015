#!/usr/bin/python

import unittest2
import socket
import json
import time
import io
import base64

HOST = '127.0.0.1'
PORT = 8000


class TestServer(unittest2.TestCase):
	usernames = ["Cristian", "Ines", "Sergio"]
	username_ids = []
	scks = []
	messages = ["Hello World!", "Hello! (Private)", "This is a public message"]
	num_con = 3
	@classmethod
	def setUpClass(cls):
		for x in range(0, TestServer.num_con):
			TestServer.scks.append(socket.socket(socket.AF_INET,
				socket.SOCK_DGRAM))
			TestServer.scks[-1].settimeout(1)

	def _new_connection(self, username, sel=0):
		data = {
			"type": "Connect",
			"username": username
		}
		return self._send_recv(data, sel)

	def _dummy_sender(self, data, selector=0):
		js = bytes(json.dumps(data), 'UTF-8')
		TestServer.scks[selector].sendto(js, (HOST, PORT))

	def _send_recv(self, data, selector=0):
		js = bytes(json.dumps(data), 'UTF-8')
		TestServer.scks[selector].sendto(js, (HOST, PORT))
		resp, addr = TestServer.scks[selector].recvfrom(65536)
		result = json.loads(resp.decode('utf-8'))
		ack = {
			"type": "ACK",
			"response_id": result["response_id"]
		}
		js = bytes(json.dumps(ack), 'UTF-8')
		TestServer.scks[selector].sendto(js, (HOST, PORT))
		return result	

	def test_00_connect(self):
		# Conectamos al primer cliente
		data = self._new_connection(TestServer.usernames[0])
		self.assertEqual(data["response"], "OK")
		TestServer.username_ids.append(data['username_id'])

	def test_00_second_connect(self):
		# Conectamos al segundo cliente
		user_id = 1
		data = self._new_connection(TestServer.usernames[user_id], user_id)
		self.assertEqual(data["response"], "OK")
		TestServer.username_ids.append(data['username_id'])

	def test_01_already_connected(self):
		# Comprobamos que si se quiere volver a conectar no lo repita y
		# devuelva su id
		data = self._new_connection(TestServer.usernames[1], 1)
		self.assertEqual(data["response"], "Already Connected")
		self.assertEqual(type(data["username_id"]), int)

	def test_01_list_users(self):
		# Enlistamos a todos los usuarios sin filtro alguno
		data = {
			"type": "List",
			"filter": ""
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_01_list_user_with_filter(self):
		# Enlistamos a los usuarios que cumplan con el filtro especificado
		data = {
			"type": "List",
			"filter": "Cris"
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["obj"]), 1)
		self.assertEqual(data["obj"][0]["username"], TestServer.usernames[0])

	def test_02_send_public_message(self):
		# Probamos a mandar un mensaje publico
		data = {
			"type": "Public_Message",
			"username_id": TestServer.username_ids[0],
			"message": TestServer.messages[0]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")


	def test_03_receive_public_message(self):
		# Comprobamos que el otro cliente reciba el mensaje enviado con anterioridad
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[1],
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(data["messages"][0]["username"],
			TestServer.usernames[0])
		self.assertEqual(data["messages"][0]["text"], TestServer.messages[0])

	def test_04_not_receive_anything(self):
		# Comprobamos que una vez leido se haya eliminado el mensaje del servidor
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[1],
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 0)

	def test_05_send_private_message(self):
		# Enviamos un mensaje privado
		data = {
			"type": "Private_Message",
			"username_id": TestServer.username_ids[1],
			"receiver_id": TestServer.username_ids[0],
			"message": TestServer.messages[1]
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")

	def test_06_receive_message(self):
		# Comprobamos que se reciba el mensaje privado enviado con anterioridad
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(data["messages"][0]["username"],
			TestServer.usernames[1])
		self.assertEqual(data["messages"][0]["text"], TestServer.messages[1])

	def test_07_connect_third(self):
		# Conectamos un tercer cliente
		user_id = 2
		data = self._new_connection(TestServer.usernames[user_id], user_id)
		self.assertEqual(data["response"], "OK")
		TestServer.username_ids.append(data['username_id'])

	def test_08_public_message(self):
		# Con tres clientes conectados enviamos un mensaje publico
		data = {
			"type": "Public_Message",
			"username_id": TestServer.username_ids[2],
			"message": TestServer.messages[2]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_08_private_message(self):
		# Con tres clientes conectados enviamos un mensaje privado a uno
		data = {
			"type": "Private_Message",
			"username_id": TestServer.username_ids[0],
			"receiver_id": TestServer.username_ids[1],
			"message": TestServer.messages[1]
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")

	def test_09_receive_multiple(self):
		# A ese que le enviamos el privado comprobamos que haya recibido dos mensajes
		# el publico y el privado
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[1],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 2)

	def test_10_check_remaining(self):
		# Comprobamos que el otro cliente pueda leer el publico
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 1)

		# Comprobamos que él que envío el mensaje publico no lo reciba
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[2],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 0)

	def test_11_send_file(self):
		filename = "oso.jpg"
		fp = io.FileIO(filename)
		byte_string = base64.b64encode(fp.read()).decode()
		fp.close()
		UDP_SIZE = 65000
		cont = 0
		byte_size = len(byte_string)
		chunks = list()
		while cont <  byte_size:
			if (cont + UDP_SIZE) > byte_size:
				chunks.append(byte_string[cont:])
			else:
				chunks.append(byte_string[cont:cont + UDP_SIZE])
			cont += UDP_SIZE
		chunk_length = len(chunks)
		data = {
			"type": "File",
			"filename": filename,
			"chunks": chunk_length,
			"sender": TestServer.usernames[0],
			"receiver": TestServer.usernames[1]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(type(data["file_id"]), int)

		chunk_data = {
			"type": "Chunk",
			"file_id": data["file_id"],
			"content": None,
			"order": -1
		}
		for i in range(0, chunk_length):
			chunk_data["order"] = i
			chunk_data["content"] = chunks[i]
			data = self._send_recv(chunk_data)
			self.assertEqual(data["response"], "OK")
		#fp1 = io.FileIO("test.png", "wb")
		#fp1.write(base64.b64decode(data["content"].encode()))
		#fp1.close()
		#self._dummy_sender(data)

	@classmethod
	def tearDownClass(cls):
		for x in range(0, TestServer.num_con):
			TestServer.scks[x].close()
		

if __name__ == '__main__':
	unittest2.main()