#Chat 2015 (Server)
----

####Installing node modules  
----  
The modules already are in the server path, but if you have problems delete the node_modules folder with
```rm -rf node_modules```. Afterwards, if you want to be able to execute coffee from you system do the following:
```
sudo npm install -g coffee-script
```
Otherwise, if you want to execute from the node_modules (./node_modules/.bin/coffee) directory run the following:
```
npm install coffee-script
```
Install the remaining dependencies:
```
npm install sqlite3
```

####Running the server
----
If you install coffeescript using **-g**:
```
coffee server.coffee
```
On the other hand, if you install it without **-g**:
```
./node_modules/.bin/coffee server.coffee
```

####Compiling and running using node
----
Run the following:  
```
coffee -c server.coffee handles.coffee
node server.js
```

####Running python tests
----
1. First you have to install the dependencies:  

  ```
  sudo pacman -Sy python-pip
  sudo pip install unittest2
  ```

2. Finally, run it:  
  ```
  python test_server.py
  ```

####API Reference
----
Go to the following link:  
- [API readme](https://github.com/mira0993/chat2015/blob/master/server/API.md)
