# This is an plugin to send xmpp messages and recieve commands from the admin

module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  util = require "util"
  Client = require 'node-xmpp-client'
  M = env.matcher

  xmppService = null

  CmdMap = []

  class XmppPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      user = @config.user
      password = @config.password
      @adminUser = @config.adminId
      @defaultUser = @config.defaultId
      env.logger.debug ("Starting xmpp Client")
      env.logger.debug ("xmpp: user= #{user}")

      xmppService = new Client ({
        jid: user,
        password: password,
        onerror: (message) => env.logger.error("xmpp error: #{message}")
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
      @setNick("pimatic")

    offline: =>
      env.logger.info ("xmpp Service offline")

    error: =>
      env.logger.info ("xmpp Service error")

    rec: (stanza) =>
      if stanza.attrs.type is 'error'
        env.logger.error '[xmpp error]' + stanza
        return
      from = stanza.attrs.from
      fromUser=from.split "/",1
      if fromUser[0] != @adminUser
        return
      switch stanza.name
        when 'message'
          @readMessage stanza
        when 'presence'
          @readPresence stanza

    setStatus: (status) =>
      xmppService.send(new Client.Stanza('presence').
      c('show').
      t('chat').
      c('status').
      t(status))

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
        to: room
        ).
        c('x', { xmlns: 'http://jabber.org/protocol/muc' }))

    acceptSubscription: (tojid) =>
      xmppService.send(new Client.Stanza('presence',
        to: tojid,
        type: 'subscribed'))

    sendMessage: (tojid, message) =>
      xmppService.send(new Client.Stanza('message',
        to: tojid,
        type: 'chat'
        ).
        c('body').
        t(message))

    createDummyParseContext = ->
      variables = {}
      functions = {}
      return M.createParseContext(variables, functions)

    readPresence: (stanza) =>
      from = stanza.attrs.from
      if(stanza.attrs.type == 'subscribe')
        @subscribe(@adminUser)
        @acceptSubscription(@adminUser)

    readMessage: (stanza) =>
      body = stanza.getChild 'body'
      from = stanza.attrs.from
      fromUser=from.split "/",1
      if body?
        message = body.getText().toLowerCase()
        env.logger.debug "Received message: #{message} from #{fromUser}"
        switch message
          when "help"
            sendstring = '\nBuilt-in commands:\n  help\n  list devices\nAvailable Events:'
            for cmdval in CmdMap
              sendstring=sendstring + '\n  ' + cmdval.getCommand()
            @sendMessage from, sendstring
            return
          when "list devices"
            Devices = @framework.deviceManager.getDevices()
            DevicesClass = @framework.deviceManager.getDeviceClasses()
            sendstring = '\nDevices :'
            for dev in Devices
              sendstring=sendstring + '\n  Name: ' + dev.name + " \tID: " + dev.id + " \t Type: " +  dev.constructor.name
            @sendMessage from, sendstring
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

  class XmppPredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework, @config) ->
      super()

    parsePredicate: (input, context) ->
      exprTokens = null
      fullMatch = null
      nextInput = null
      matchingUnit = null
      CommandToken = null

      setCommand = (m, tokens) => CommandToken = tokens

      m = M(input, context)
        .match('receiced ')
        .matchString(setCommand)

      if m.hadMatch()
        fullMatch = m.getFullMatch()
        nextInput = m.getRemainingInput()

      if fullMatch?
        return {
          token: fullMatch
          nextInput: input.substring(fullMatch.length)
          predicateHandler: new CommandBotPredicateHandler(@framework, CommandToken)
        }
      else return null


  class CommandBotPredicateHandler extends env.predicates.PredicateHandler
    constructor: (framework, @Command) ->
      super()
      @_variableManager = framework.variableManager

    setup: ->
      @_variableManager.notifyOnChange(@Command, @expChangeListener = () =>
        @_lastTime = null
      )
      xmpp_connection.registerCmd this
      super()

    getValue: -> Promise.resolve false
    getType: -> 'event'
    getCommand: -> "#{@Command}"

    destroy: ->
      xmpp_connection.deregisterCmd this
      if @expChangeListener?
        @_variableManager.cancelNotifyOnChange(@expChangeListener)
        @expChangeListener = null
      @destroyed = yes
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
          msg = {
              message: message
              tojid: tojid
          }
          stanza = new Client.Stanza('message',
              to: tojid,
              type: 'chat'
            ).
            c('body').
            t(message)
          xmppService.send(stanza)
          return Promise.resolve(__("xmpp message sent successfully"))

      )

  module.exports.XmppActionHandler = XmppActionHandler

  xmpp_connection = new XmppPlugin
  # and return it to the framework.
  return xmpp_connection
