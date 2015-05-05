#!/usr/bin/python

import unittest2
import socket
import json
import time
import base64
import uuid

HOST = '127.0.0.1'
PORT = 8000


class TestServer(unittest2.TestCase):
	usernames = ["Cristian", "Ines", "Sergio"]
	username_ids = []
	scks = []
	messages = ["Hello World!", "Hello! (Private)",
		"This is a public message", "This message is blocked by someone"]
	filenames = ["oso.jpg", "test.mp3"]
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
		data["request_uuid"] = str(uuid.uuid4())
		js = bytes(json.dumps(data), 'UTF-8')
		TestServer.scks[selector].sendto(js, (HOST, PORT))
		resp, addr = TestServer.scks[selector].recvfrom(65536)
		result = json.loads(resp.decode('utf-8'))
		ack = {
			"type": "ACK",
			"ack_uuid": result["response_uuid"]
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
			"filter": "",
			"username_id": TestServer.username_ids[0]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_01_list_user_with_filter(self):
		# Enlistamos a los usuarios que cumplan con el filtro especificado
		data = {
			"type": "List",
			"filter": "Cris",
			"username_id": TestServer.username_ids[0]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["obj"]), 1)
		self.assertEqual(data["obj"][0]["username"], TestServer.usernames[0])
		self.assertEqual(data["obj"][0]["status"], 0)

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
		self.assertEqual(data["messages"][0]["type"], "public")
		self.assertEqual(data["messages"][0]["username_id"],
			TestServer.username_ids[0])
		self.assertEqual(data["messages"][0]["text"], TestServer.messages[0])

	def test_04_not_receive_none(self):
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
		self.assertEqual(data["messages"][0]["type"], "private")
		self.assertEqual(data["messages"][0]["username_id"],
			TestServer.username_ids[1])
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
		self.assertRegexpMatches(data["messages"][0]["type"], r'(public)|(private)')
		self.assertRegexpMatches(data["messages"][1]["type"], r'(public)|(private)')
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
		self.assertEqual(data["messages"][0]["type"], "public")

		# Comprobamos que él que envío el mensaje publico no lo reciba
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[2],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 0)

	def test_11_send_file(self):
		f_uuid = str(uuid.uuid4())
		filename = TestServer.filenames[0]
		#filename = TestServer.filenames[1]
		byte_string = None
		with open(filename, "rb") as fp:
			byte_string = base64.b64encode(fp.read()).decode()

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
			"file_uuid": f_uuid,
			"chunks": chunk_length,
			"sender": TestServer.username_ids[0],
			"receiver": TestServer.username_ids[1]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(data["file_uuid"], f_uuid)

		chunk_data = {
			"type": "S_Chunk",
			"file_uuid": f_uuid,
			"content": None,
			"order": -1
		}

		for i in range(0, chunk_length):
			chunk_data["order"] = i
			chunk_data["content"] = chunks[i]
			data = self._send_recv(chunk_data)
			self.assertEqual(data["response"], "OK")
	
	def test_12_push_file(self):
		user_id = 1
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[user_id],
		}
		file_info = self._send_recv(data, user_id)["messages"][0]
		f_uuid = file_info["file_uuid"]

		# Comprobamos si realmente lo bloqueo y ya no regresa un mensaje pendiente
		rep_data = {
			"type": "Push",
			"username_id": TestServer.username_ids[user_id],
		}
		rep = self._send_recv(rep_data, user_id)
		self.assertEqual(rep["response"], "OK")
		self.assertEqual(len(rep["messages"]), 0)

		# Continuamos con la descarga
		data = {
			"type": "R_Chunk",
			"file_uuid": f_uuid,
			"num_part": -1
		}
		content = list()
		for x in range(0, file_info["chunks"]):
			data["num_part"] = x
			result = self._send_recv(data)
			content.append(result["content"])
		with open("2{0}".format(file_info["filename"]), "wb") as fp:
			for item in content:
				fp.write(base64.b64decode(item.encode()))

	def test_12_disconnect_third(self):
		data = {
			"type": "Disconnect",
			"username_id": TestServer.username_ids[2]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_13_list_users(self):
		# Enlistamos a todos los usuarios sin filtro alguno
		data = {
			"type": "List",
			"filter": "",
			"username_id": TestServer.username_ids[0]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		for item in data["obj"]:
			if item["username"] == TestServer.username_ids[2]:
				self.assertEqual(item["status"], -1)

	def test_14_connect_third_again(self):
		# Conectamos un tercer cliente
		user_id = 2
		data = self._new_connection(TestServer.usernames[user_id], user_id)
		self.assertEqual(data["response"], "OK")
		TestServer.username_ids.append(data['username_id'])

	def test_15_block_user(self):
		data = {
			"type": "Block",
			"blocker": TestServer.username_ids[0],
			"blocked": TestServer.username_ids[2]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_16_list_users(self):
		# Enlistamos a todos los usuarios sin filtro alguno
		data = {
			"type": "List",
			"filter": "",
			"username_id": TestServer.username_ids[0]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		for item in data["obj"]:
			if item["username"] == TestServer.username_ids[2]:
				self.assertEqual(item["blocked"], -1)

	def test_16_blocked_private_message(self):
		user_id = 2
		data = {
			"type": "Private_Message",
			"username_id": TestServer.username_ids[user_id],
			"receiver_id": TestServer.username_ids[0],
			"message": TestServer.messages[1]
		}
		data = self._send_recv(data, user_id)
		self.assertEqual(data["response"], "OK")

	def test_17_not_receive_message(self):
		# Comprobamos que no se reciba mensahe
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 0)

	def test_18_send_public_message(self):
		# Probamos a mandar un mensaje publico
		user_id = 2
		data = {
			"type": "Public_Message",
			"username_id": TestServer.username_ids[user_id],
			"message": TestServer.messages[3]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_19_not_receive_message(self):
		# Checamos que no haya quedado mensaje en el inbox del bloqueado
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 0)

	def test_19_receive_message(self):
		# Limpiamos el mensaje que quedo disponible
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[1],
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(data["messages"][0]["type"], "public")
		self.assertEqual(data["messages"][0]["username_id"],
			TestServer.username_ids[2])
		self.assertEqual(data["messages"][0]["text"], TestServer.messages[3])

	def test_20_send_private_to_blocker(self):
		user_id = 1
		data = {
			"type": "Private_Message",
			"username_id": TestServer.username_ids[user_id],
			"receiver_id": TestServer.username_ids[0],
			"message": TestServer.messages[1]
		}
		data = self._send_recv(data, user_id)
		self.assertEqual(data["response"], "OK")

	def test_21_blocker_receive_private(self):
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 1)
		self.assertEqual(data["messages"][0]["username_id"], TestServer.username_ids[1])

	def test_22_send_public_from_not_blocked(self):
		user_id = 1
		data = {
			"type": "Public_Message",
			"username_id": TestServer.username_ids[user_id],
			"message": TestServer.messages[3]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_23_receive_public_from_blocker(self):
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(len(data["messages"]), 1)

	def test_24_unblock(self):
		data = {
			"type": "Unblock",
			"blocker": TestServer.username_ids[0],
			"blocked": TestServer.username_ids[2]
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")

	def test_25_unblocked_private_message(self):
		data = {
			"type": "Private_Message",
			"username_id": TestServer.username_ids[2],
			"receiver_id": TestServer.username_ids[0],
			"message": TestServer.messages[1]
		}
		data = self._send_recv(data, 1)
		self.assertEqual(data["response"], "OK")

	def test_26_receive_message_from_unblocked(self):
		# Limpiamos el mensaje que quedo disponible
		data = {
			"type": "Push",
			"username_id": TestServer.username_ids[0],
		}
		data = self._send_recv(data)
		self.assertEqual(data["response"], "OK")
		self.assertEqual(data["messages"][0]["type"], "private")
		self.assertEqual(data["messages"][0]["username_id"],
			TestServer.username_ids[2])
		self.assertEqual(data["messages"][0]["text"], TestServer.messages[1])
	
	@classmethod
	def tearDownClass(cls):
		for x in range(0, TestServer.num_con):
			TestServer.scks[x].close()
		

if __name__ == '__main__':
	unittest2.main()