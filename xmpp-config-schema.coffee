module.exports = {
  title: "xmpp config options"
  type: "object"
  required: ["user", "password" , "adminId"]
  properties:
    user:
      description: "xmpp user name"
      type: "string"
      required: yes
    password:
      description: "xmpp user password"
      type: "string"
      required: yes
    adminId:
      description: "xmpp admin user"
      type: "string"
      required: yes
    defaultId:
      description: "tojid default user"
      type: "string"
      required: yes
    keepaliveInterval:
      description: "keep alive interval"
      type: "integer"
      default: 5
}
