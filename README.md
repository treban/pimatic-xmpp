pimatic-xmpp
=======================

> **beta stadium !**

This plugin provides an xmpp aka jabber messaging system for [pimatic](https://pimatic.org/).
#### Features
* Send messages to users
* Reveive commands from users

### Service dependencies

The plugin needs a valid user account on any xmpp service.

* You can use a public jabber/xmpp service
* or install a local service on your pimatic server like ejabberd

For the raspberry pi there are several guides to install an ejabberd service.

### Installation

Just activate the plugin in your pimatic config. The plugin manager automatically installs
the package with his dependencys.

### Configuration

You can load the plugin by adding following in the config.json from your pimatic server:

    {
      "plugin": "xmpp",
      "user": "pimatic-user@server.org",
      "password": "secretpw",
      "adminId": "admin-user@server.org",
      "defaultId": "default-user@server.org",
      "nickId": "pimatic"
      "keepaliveInterval": 5
    }

The config item adminId is the access controle for receiving messages.

Only messages from this user will be accepted.

### Usages
#### Chat client

The messaging system implements a chat bot which answers questions
and execute actions.

The bot uses the rule action syntax. So all devices are out of the box accessible.

For example:
```
toggle device1
switch device2 on
set temp of heating to 28
list devices
get device heating
get all devices
```


Following commands are predefiend:

Built-in commands:
* help
* list devices
* get all devices
* get device **name or id**

Available actions:
* "created predicates in rules"


#### Provided predicates
The messaging system provides a **_received_** event.
```
received "do action"
```

#### Provided actions
The messaging system provides a **_send_** event.
```
send chat tojid:"admin-user@server.org" message:"triggerd event has occurred"
```

### ToDoList
* chatrooms for multiuser enviroments (password protected)
* built-in server ? for easy use of plugin


### ChangeLog
* 0.0.3
  First public version.
  Use xmpp system over the rule section: predicates and action handler

* 0.0.4
  - Full integrated command parser for all available pimatic actions
  - list all devices
  - xmpp core improvements; subscribe to admin user
  - some bug fixes  
* 0.0.5
  - code cleanup
  - autoreconnect
  - new Device: xmppUser as presence device
  - get commands for devices
  - security fixes
* 0.0.6 BUGFIX
* 0.0.7 BUGFIX

This plugin depends on [node-xmpp-client](https://github.com/node-xmpp/node-xmpp/tree/master/packages/node-xmpp-client).
