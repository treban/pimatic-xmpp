# This is an plugin to send xmpp messages and recieve commands from the admin

module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  util = require "util"
  Client = require 'node-xmpp-client'
  M = env.matcher

  class XmppPlugin extends env.plugins.Plugin

    xmppService = null
    CmdMap = []
    jidBook = []
    rosterBook = []

    init: (app, @framework, @config) =>
      @user = @config.user
      password = @config.password
      @adminUser = @config.adminId
      @defaultUser = @config.defaultId
      @nickId = @config.nickId
    #  @roomName = @config.roomName
    #  @roomPassword = @config.roomPassword

      env.logger.debug ("Starting xmpp Client")
      env.logger.debug ("xmpp: user= #{@user}")
      deviceConfigDef = require("./xmpp-device-schema")

      xmppService = new Client ({
        jid: @user,
        password: password,
        reconnect: true,
        onerror: (message) => env.logger.error("xmpp error: #{message}")
      })

      @framework.deviceManager.registerDeviceClass("XmppPresence", {
        configDef: deviceConfigDef.XmppPresence,
        createCallback: (config) => new XmppPresence(config)
      })

      xmppService.connection.socket.on 'error' , @error
      xmppService.on 'online', @.online
      xmppService.on 'error', @.error
      xmppService.on 'offline', @.offline
      xmppService.on 'stanza', @.rec

      @framework.ruleManager.addActionProvider(new XmppActionProvider @framework, @config)
      @framework.ruleManager.addPredicateProvider(new XmppPredicateProvider(@framework, @config))

    online: =>
      env.logger.info ("xmpp Service Online")
      xmppService.connection.socket.setTimeout 0
      xmppService.connection.socket.setKeepAlive true, @config.keepaliveInterval
      @setStatus("ready")
      @setNick(@nickId)
      @getRoster()

    offline: =>
      env.logger.info ("xmpp Service offline")

    error: =>
      env.logger.info ("xmpp Service error")

    rec: (stanza) =>
      env.logger.debug '[xmpp recieved message:]' + stanza
      if stanza.attrs.type is 'error'
        env.logger.error '[xmpp error]' + stanza
        return
      from = stanza.attrs.from
      fromUser=""
      fromUser=from?.split "/",1
      flag = 0
      for jid in jidBook
        if jid.getJid() in fromUser
          flag = 1
      if fromUser[0] == @adminUser or fromUser[0] == @user or flag == 1
        switch stanza.name
          when 'message'
            @readMessage stanza
          when 'presence'
            @readPresence stanza
          when 'iq'
            @readIq stanza

    setStatus: (status) =>
      xmppService.send(new Client.Stanza('presence').
      c('show').t('chat').
      c('status').t(status))

    setNick: (nick) =>
      xmppService.send(new Client.Stanza('presence').
      c('nick', xmlns: 'http://jabber.org/protocol/nick').
      t(nick))

    subscribe: (tojid) =>
      xmppService.send(new Client.Stanza('presence',
        to: tojid,
        type: 'subscribe'))

    joinRoom: (room) =>
      xmppService.send(new Client.Stanza('presence',
        to: room ).
        c('x', { xmlns: 'http://jabber.org/protocol/muc' }).
        c('password').t(password))

    acceptSubscription: (tojid) =>
      xmppService.send(new Client.Stanza('presence',
        to: tojid,
        type: 'subscribed'))

    sendMessage: (tojid, message) =>
      xmppService.send(new Client.Stanza('message',
        to: tojid,
        type: 'chat').
        c('body').
        t(message))

    getRoster: () =>
      xmppService.send(new Client.Stanza('iq',
        id: 'roster_1',
        type: 'get').
        c('query', { xmlns: 'jabber:iq:roster' }))

    createDummyParseContext = ->
      variables = {}
      functions = {}
      return M.createParseContext(variables, functions)

    readPresence: (stanza) =>
      from = stanza.attrs.from
      fromUser=from.split "/",1
      if(stanza.attrs.type == 'subscribe')
        @subscribe(@adminUser)
        @acceptSubscription(@adminUser)
        return
      if(fromUser == @user)
        return
      if(stanza.attrs.type == 'unavailable')
        for jid in jidBook
          if jid.getJid() in fromUser
            jid._setPresence(false)
        return
      for jid in jidBook
        if  jid.getJid() in fromUser
          jid._setPresence(true)

    readIq: (stanza) =>
      #if stanza.attrs.type == 'result' and stanza.attrs.id == 'roster_1'
        #rosterBook.push new XmppUser(stanza.getChild('query', 'jabber:iq:roster').getChild('item').attrs?.jid?)

    readMessage: (stanza) =>
      body = stanza.getChild 'body'
      from = stanza.attrs.from
      fromUser=from.split "/",1
      if body?
        message = body.getText().toLowerCase()
        env.logger.debug "Received message: #{message} from #{fromUser}"
        switch
          when /^help$/.test(message)
            sendstring = '\nBuilt-in commands:\n  help\n  list devices\n  get all devices\n  get device *** (by name or id)\n Available actions:'
            for cmdval in CmdMap
              sendstring=sendstring + '\n  ' + cmdval.getCommand()
            @sendMessage from, sendstring
            return
          when /^list devices$/.test(message)
            Devices = @framework.deviceManager.getDevices()
            DevicesClass = @framework.deviceManager.getDeviceClasses()
            sendstring = '\nDevices :'
            for dev in Devices
              sendstring = sendstring + '\nName: ' + dev.name + " \tID: " + dev.id + " \t Type: " +  dev.constructor.name + ""
            @sendMessage from, sendstring
            return
          when /^get all devices$/.test(message)
            Devices = @framework.deviceManager.getDevices()
            sendstring = '\nDevices :'
            for dev in Devices
              sendstring = sendstring + '\n-------------------\nName: ' + dev.name + " \tID: " + dev.id + " \t Type: " +  dev.constructor.name
              for name of dev.attributes
                sendstring=sendstring + '\n\t' + name + " " + dev.getLastAttributeValue(name) + ""
            @sendMessage from, sendstring
            return
          when /^get device [\w.-]+/.test(message)
            obj=message.split "device",4
            Devices = @framework.deviceManager.getDevices()
            for dev in Devices
              if ( obj[1].substring(1) == dev.id.toLowerCase() ) or ( obj[1].substring(1) == dev.name.toLowerCase() )
                sendstring = '\nName: ' + dev.name + " \tID: " + dev.id + " \t Type: " +  dev.constructor.name
                for name of dev.attributes
                  sendstring=sendstring + '\n\t' + name + " " + dev.getLastAttributeValue(name) + ""
                @sendMessage from, sendstring
                return
            @sendMessage from, "device not found"
            return
        if /execute/i.test(message) # Prevent to run a shell execute (for security reasons!)
          return
        for cmdval in CmdMap
          if cmdval.getCommand().toLowerCase() == message
            cmdval.emit('change', 'event')
            @sendMessage from, "done"
            return
        for act in @framework.ruleManager.actionProviders
          context = createDummyParseContext()
          han = act.parseAction(message,context)
          if han?
            han.actionHandler.executeAction()
            @sendMessage from, "done"
            return
        @sendMessage from, "Command not found"

    registerCmd: (@Cmd) =>
      CmdMap.push @Cmd
      env.logger.debug "Register command: #{@Cmd.getCommand()}"

    deregisterCmd: (@Cmd) =>
      CmdMap.splice(CmdMap.indexOf(@Cmd),1)
      env.logger.debug "Deregister command: #{@Cmd.getCommand()}"

    registerPresence: (@user) =>
      env.logger.debug "Register Presence of: #{@user.jid}"
      jidBook.push @user

    deregisterPresence: (@user) =>
      jidBook.splice(jidBook.indexOf(@user),1)
      env.logger.debug "Deregister command: #{@user.jid}"

  class XmppPredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework, @config) ->
      super()

    parsePredicate: (input, context) ->
      fullMatch = null
      nextInput = null
      recCommand = null

      setCommand = (m, tokens) => recCommand = tokens

      m = M(input, context)
        .match('receiced ')
        .matchString(setCommand)

      if m.hadMatch()
        fullMatch = m.getFullMatch()
        nextInput = m.getRemainingInput()

      if fullMatch?
        assert typeof recCommand is "string"
        return {
          token: fullMatch
          nextInput: input.substring(fullMatch.length)
          predicateHandler: new XmppPredicateHandler(@framework, recCommand)
        }
      else return null

  class XmppPredicateHandler extends env.predicates.PredicateHandler
    constructor: (framework, @Command) ->
      super()

    setup: ->
      xmpp_messageBot.registerCmd this
      super()

    getValue: -> Promise.resolve false
    getType: -> 'event'
    getCommand: -> "#{@Command}"

    destroy: ->
      xmpp_messageBot.deregisterCmd this
      super()

  class XmppActionProvider extends env.actions.ActionProvider

    constructor: (@framework, @config) ->
      return

    parseAction: (input, context) =>

      defaultId = @config.defaultId
      defaultMessage = "Test message! - Please define a valid message in your rule"

      strToTokens = (str) => ["\"#{str}\""]

      tojidTokens = strToTokens defaultId
      messageTokens = strToTokens defaultMessage

      setjid = (m, tokens) => tojidTokens = tokens
      setMessage = (m, tokens) => messageTokens = tokens

      m = M(input, context)
        .match('send ', optional: yes)
        .match(['push','chat','notification'])

      next = m.match(' tojid:').matchStringWithVars(setjid)
      if next.hadMatch() then m = next

      next = m.match(' message:').matchStringWithVars(setMessage)
      if next.hadMatch() then m = next

      if m.hadMatch()
        match = m.getFullMatch()
        assert Array.isArray(tojidTokens)
        assert Array.isArray(messageTokens)
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new XmppActionHandler(
            @framework, tojidTokens, messageTokens
          )
        }
      else
        return null

  class XmppActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @tojidTokens, @messageTokens) ->

    executeAction: (simulate, context) ->
      Promise.all( [
        @framework.variableManager.evaluateStringExpression(@tojidTokens)
        @framework.variableManager.evaluateStringExpression(@messageTokens)
      ]).then( ([tojid, message]) =>
        if simulate
          return __("would push message \"%s\" to tojid \"%s\"", message, tojid)
        else
          xmpp_messageBot.sendMessage(tojid,message)
          return Promise.resolve(__("xmpp message sent successfully"))
      )

  class XmppPresence extends env.devices.PresenceSensor
    constructor: (@config, deviceNum) ->
      @name = @config.name
      @id = @config.id
      @jid = @config.jid
      @_presence = lastState?.presence?.value or false
      @count = 0
      xmpp_messageBot.registerPresence this
      super()

    getJid: ->
      return @jid

    destroy: ->
      xmpp_messageBot.deregisterPresence this
      super()

  class XmppUser

    @callback = null

    constructor: (@jid) ->
      @state = false

    getJid: =>
      return @jid

    getState: =>
      return @state

    setState: (newstate) =>
      if @state is newstate then return
      @state = newstate

  module.exports.XmppActionHandler = XmppActionHandler

  xmpp_messageBot = new XmppPlugin
  # and return it to the framework.
  return xmpp_messageBot
