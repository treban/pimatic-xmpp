module.exports = {
  title: "pimatic-xmpp device config schemas"
  XmppPresence: {
    title: "xmpp Presence config options"
    type: "object"
    extensions: ["xPresentLabel", "xAbsentLabel"]
    properties:
      jid:
        description: "the jabber id"
        type: "string"
        default: ""
  }
}
