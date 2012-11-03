# Dependencies
express = require 'express'
assets = require 'connect-assets'
path = require 'path'
pwd = require 'pwd'

###
Handle MongoDB
###
if process.env.VCAP_SERVICES
	env = JSON.parse(process.env.VCAP_SERVICES)
	mongo = env["mongodb-1.8"][0]["credentials"]
else
	mongo =
		hostname: "localhost"
		port: 27017
		groupname: ""
		password: ""
		name: ""
		db: "govNext"
generate_mongo_url = (obj) ->
	obj.hostname = (obj.hostname or "localhost")
	obj.port = (obj.port or 27017)
	obj.db = (obj.db or "govNext")
	if obj.groupname and obj.password
		"mongodb://" + obj.groupname + ":" + obj.password + "@" + obj.hostname + ":" + obj.port + "/" + obj.db
	else
		"mongodb://" + obj.hostname + ":" + obj.port + "/" + obj.db

mongourl = generate_mongo_url(mongo)
mongoose = require 'mongoose'
db = mongoose.createConnection mongourl
Schema = mongoose.Schema
db.on 'error', console.error.bind(console, 'Connection error:')
db.once 'open', () -> 
	console.log "You'll see '1' if the databases are ready."
	console.log "Login DB Response: #{Login.db.readyState}"
	console.log "Group DB Response: #{Login.db.readyState}"

###
Mongoose Schemas
###
loginSchema = new Schema
	email: String
	salt: String
	hash: String
	_group: Schema.Types.ObjectId
Login = db.model 'Login', loginSchema
groupSchema = new Schema
	primaryContact:
		name: String
		email: String
		phone: String
	groupInformation:
		affiliation: String
		address: String
		city: String
		province: String
		postalCode: String
		fax: String
	youth: [Schema.Types.ObjectId]
	chaperones: [Schema.Types.ObjectId]
	youngAdults: [Schema.Types.ObjectId]
Group = db.model 'Group', groupSchema

###
Configure the app
###
app = express()
app.configure ->
	app.set "views", "#{__dirname}/views"
	app.set "view engine", "jade"
	#app.use express.compress()
	app.use express.favicon()
	app.use express.logger("dev")
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use assets
		src: 'public'
	app.use express.cookieParser(process.env.COOKIE_SECRET or 'test')
	app.use express.session
		secret: process.env.SESSION_SECRET or 'test'
		store: new express.session.MemoryStore
	app.use app.router
	app.use express.static "#{__dirname}/public"
	app.use (req, res) ->
		res.status 404
		res.redirect "/"

###
GET routes
###
app.get '/', (req, res) ->
	res.render 'index',
		title: "Home"
		group: req.session.group || null

app.get '/privacy', (req, res) ->
	res.render 'privacy',
		title: "Privacy Policy"
		group: req.session.group || null

app.get '/account', (req, res) ->
	res.render 'account/index',
		title: "Account Management"
		group: req.session.group || null

app.get '/account/signup', (req, res) ->
	res.render 'account/signup',
		title: "Signup"
		group: req.session.group || null

app.get '/account/login', (req, res) ->
	res.render 'account/login',
		title: "Login"
		group: req.session.group || null

app.get '/account/', (req, res) ->
	if req.session.group is null
		res.redirect '/'
	else
		res.render 'account/index',
			title: "Account Management"
			group: req.session.group

# Error Pages
app.get '/404', (req, res) ->
	res.render 'index',
		title: "404"
		group: req.session.group || null

###
API routes
###
app.post '/api/login', (req, res) ->
	Login.findOne
		email: req.body.email
		(err, login) ->
			if err or not login
				res.send "You're not signed up."
			else
				pwd.hash req.body.pass, login.salt, (err, hash) ->
					if login.hash is hash
						Group.findById login._group, (err, group) ->
								req.session.group = group
								res.redirect '/'
					else
						res.send "Wrong password. <a href='/'>Go back</a>"

app.post '/api/signup', (req, res) ->
	Login.findOne
		email: req.body.email
		(err, found) ->
			if err or found or req.body.pass is not req.body.passConfirm
				res.send "Your passwords did not match, or you're already signed up."
			else
				pwd.hash req.body.pass, (err, salt, hash) ->
					group = new Group
						primaryContact:
							email: req.body.email
							name: req.body.name
							phone: req.body.phone
						groupInformation:
							affiliation: req.body.affiliation
							address: req.body.address
							city: req.body.city
							province: req.body.province
							postalCode: req.body.postalCode
							fax: req.body.fax
					group.save (err, group) -> 
							if err
								res.send "There was an error saving your information."
							else
								login = new Login
									email: req.body.email
									salt: salt
									hash: hash
									_group: group._id
								login.save (err) ->
									if err
										res.send "There was an error saving your login."
									else
										req.session.group = group
										res.redirect '/'

app.post '/api/logout', (req, res) ->
	req.session.destroy (err) ->
		if err
			console.log err
		res.redirect "/"

###
Start listening.
###
app.listen process.env.VCAP_APP_PORT or 8080
console.log "Now listening..."