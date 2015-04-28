API Reference
----  
All the responses have an attribute **"response"**, if the response was successful it will be and **"OK"**.
Otherwise, it will be an error message. Also, it has a "response_id" attribute which is used to acknowledge
that message.

**Important:** Remember that after you receive the response from the server, it will expect an acknowledgement.
If the server doesn't receives anything it will send again the response. **The "ACK" type is the only one that
doesn't return anything.**

###Acknowlegement
----
*Send:*
```
{
  "type": "ACK",
  "ack_uuid": <UUID_FROM_CLIENT> (STRING)
}
```
*No response.*

#####Block an user
----
*Send:*
```
{
  "type": "Block",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "blocker": <USERNAME_ID_OF_THE_USER_WHICH_WANTS_TO_BLOCK_SOMEONE> (INTEGER),
  "blocked": <USERNAME_ID_OF_THE_USER_WHICH_WANTS_TO_BLOCK> (INTEGER),
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING)
}
```

#####Unblock an user
----
*Send:*
```
{
  "type": "Unblock",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "blocker": <USERNAME_ID_OF_THE_USER_WHICH_WANTS_TO_UNBLOCK_SOMEONE> (INTEGER),
  "blocked": <USERNAME_ID_OF_THE_USER_WHICH_WANTS_TO_UNBLOCK> (INTEGER),
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING)
}
```

#####Connecting to the server
----
*Send:*
```
{
  "type": "Connect",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "username": <USERNAME> (STRING)
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING),
  "username_id": <USERNAME_ID_TO_IDENTIFY_THE_USER> (INTEGER)
}
```

#####Disconnecting from the server
----
*Send:*
```
{
  "type": "Disconnect",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "username_id": <USERNAME_ID> (INTEGER)
}
```
*Response:*
```
{
  "response": "OK" or "'You weren't connected",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING),
  "username_id": <USERNAME_ID> (INTEGER)
}
```

#####List users
----
*Send:*
```
{
  "type": "List",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "username_id": <USERNAME_ID> (INTEGER),
  "filter": <FILTER_TO_USE> or "" [empty to retrieve all] (STRING),
}
```
*Response:*
```
{
  "response": "OK" (Always, even if it the user list was empty),
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING),
  "obj": [
    {
      "id": <USERNAME_ID> (INTEGER),
      "username": <USERNAME> (STRING),
      "blocked": 0 (Not blocked) or -1 (Blocked),
      "status": 0 (Connected) or -1 (Disconnected)
    },
    ... (It could be more or empty)
  ]
}
```

#####Push from the server
----
*Send:*
```
{
  "type": "PUSH",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "username_id": <USERNAME_ID> [Receiver's id] (INTEGER)
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING),
  "messages": [
    {
      "type": "public" or "private",
      "username": <SENDER_NAME> (STRING),
      "text": <MESSAGE_TEXT> (STRING)
    }
    ... (It could be more or empty)
    ... (If it is a file is the following format: )
    {
      "type": "file",
      "file_id": <FILE_ID> [Save it! It helps in retrieving the file chunks] (INTEGER),
      "username": <SENDER_NAME> (STRING),
      "filename": <FILENAME> [Save it! It helps to save the file when you have all the chunks] (STRING),
      "chunks": <CHUNKS_NUMBER> [It helps to know how many times the socket needs to receive a chunk] (INTEGER)
    }
  ]
}
```

#####Receive chunk (used as part of retrieving a file from the server)
----
*TODO*

#####Send chunk (used as part of sending a file from the server)
----
*TODO*

#####Send file (only header)
----
*Send:*
```
{
  "type": "File",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "filename": <FILENAME> (STRING),
  "CHUNKS": <NUMBER_OF_CHUNKS> (INTEGER),
  "sender": <SENDER_ID> (INTEGER),
  "receiver": <RECEIVER_ID> (INTEGER)
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING),
  "file_id": <FILE_ID> [Save it! It helps in sending the chunks to the server] (INTEGER)
}
```

#####Send private message
----
*Send:*
```
{
  "type": "Private_Message",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "username_id": <SENDER_ID> (INTEGER),
  "receiver_id": <RECEIVER_ID> (INTEGER),
  "message": <MESSAGE_TEXT> (STRING)
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING),
}
```

#####Send public message
----
```
{
  "type": "Private_Message",
  "request_uuid": <UUID_FROM_CLIENT> (STRING),
  "username_id": <SENDER_ID> (INTEGER),
  "message": <MESSAGE_TEXT> (STRING)
}
```
*Response:*
```
{
  "response": "OK",
  "response_uuid": <UUID_FROM_CLIENT_RETURNED_BY_THE_SERVER> (STRING)
}
```
