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
      env.logger.debug("Starting xmpp Client")
      user = @config.user
      password = @config.password
      @adminUser = @config.adminId
      @defaultUser = @config.defaultId
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

      @framework.ruleManager.addPredicateProvider(new CommandBotPredicateProvider(@framework, @config))

    online: =>
      env.logger.info ("xmpp Service Online")
      xmppService.connection.socket.setTimeout 0
      xmppService.connection.socket.setKeepAlive true, @config.keepaliveInterval
      presence = new Client.Stanza 'presence'
      presence.c('nick', xmlns: 'http://jabber.org/protocol/nick').t('pimatic')
      xmppService.send presence

    offline: =>
      env.logger.info ("xmpp Service offline")

    error: =>
      env.logger.info ("xmpp Service error")

    rec: (stanza) =>
      if stanza.attrs.type is 'error'
        env.logger.error '[xmpp error]' + stanza
        return
      switch stanza.name
        when 'message'
          @readMessage stanza

    sendMessage: (tojid, message) =>
  	  xmppService.send(new Client.Stanza('message',
            to: tojid,
            type: 'chat'
          ).
          c('body').
          t(message))

    readMessage: (stanza) =>
      body = stanza.getChild 'body'
      from = stanza.attrs.from
      message = body.getText().toLowerCase()
      env.logger.debug "Received message: #{message} from #{from}"
      @fromUser=from.split "/",1

      if  @fromUser[0] == @adminUser
        switch message
          when 'help'
            sendstring = 'Built-in commands:\n  help\nAvailable Events:'
            for cmdval in CmdMap
              sendstring=sendstring + '\n  ' + cmdval.getCommand()
            @sendMessage from, sendstring
            return
        for cmdval in CmdMap
          if cmdval.getCommand().toLowerCase() == message
            cmdval.emit('change', 'event')
            @sendMessage from, "done"
            return
        @sendMessage from, "Command not found"
      else
        @sendMessage from, "What do you want?!"

    registerCmd: (@Cmd) =>
      CmdMap.push @Cmd
      env.logger.debug "Register command: #{@Cmd.getCommand()}"

    deregisterCmd: (@Cmd) =>
      CmdMap.splice(CmdMap.indexOf(@Cmd),1)
      env.logger.debug "Deregister command: #{@Cmd.getCommand()}"

  xmpp_connection = new XmppPlugin

  # Provides received message
  class CommandBotPredicateProvider extends env.predicates.PredicateProvider

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
          nextInput: input.substring(fullMatch.length) # nextInput
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
          env.logger.debug "xmpp debug: send"
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

  # and return it to the framework.
  return xmpp_connection
