pimatic-xmpp
=======================

> **beta stadium !**

This plugin provides an xmpp aka jabber messaging system for [pimatic](https://pimatic.org/).
####Features
* Send messages to users
* Reveive commands from users

###Service dependencies

The plugin needs a valid user account on any xmpp service. 

* You can use a public jabber/xmpp service
* or install a local service on your pimatic server like ejabberd

For the raspberry pi there are several guides to install an ejabberd service.

###Installation

Extract the plugin content in your pimatic plugin directory:
```
cd <PATH-TO-PIMATIC>/node_modules/
git clone https://github.com/treban/pimatic-xmpp.git
```

###Software dependencies

This plugin depends on [node-xmpp-client](https://github.com/node-xmpp/node-xmpp/tree/master/packages/node-xmpp-client).

After cloning the git repository change in to the plugin directory and install the xmpp-client over the npm packages manager.
```
cd ./pimatic-xmpp
npm install node-xmpp-client 
```

###Configuration

You can load the plugin by adding following in the config.json from your pimatic server: 

    {
      "plugin": "xmpp",
      "user": "pimatic-user@server.org",
      "password": "secretpw",
      "adminId": "admin-user@server.org",
      "keepaliveInterval": 5
    }

The config item adminId is the access controle for receiving messages.

Only messages from this user will be accepted. 
 
###Usages
####Provided predicates
The messaging system provides a **_received_** event. 
```
received "do action" 
```

####Provided actions
The messaging system provides a **_send_** event.
```
send chat tojid:"admin-user@server.org" message:"triggerd event has occurred"
```

####Chat client

The messaging system implements a chat bot which answers questions. 
Following commands are predefiend:

Built-in commands:
* help

Available events: 
* "created predicates"

###ToDoList
* list devices
* possibility to interact with devices

