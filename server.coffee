# Dependencies
express = require 'express'
assets = require 'connect-assets'
path = require 'path'
pwd = require 'pwd'
RedisStore = require('connect-redis')(express)
mongo = require 'mongojs'
db = mongo 'govNext', ['logins', 'users']


###
Configure the app
###
app = express()
MemStore = express.session.MemoryStore
app.configure ->
	app.set "views", "#{__dirname}/views"
	app.set "view engine", "jade"
	app.use express.compress()
	app.use express.favicon()
	app.use express.logger("dev")
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use assets
		src: 'public'
	app.use express.cookieParser(process.env.COOKIE_SECRET or 'test')
	app.use express.session
		secret: process.env.SESSION_SECRET or 'test'
		store: new RedisStore
	app.use app.router
	app.use express.static "#{__dirname}/public"
	app.use (req, res) ->
		res.status 404
		res.redirect "/404"

###
GET routes
###
app.get '/', (req, res) ->
	res.render 'index', { title: "Home", user: req.session.user || null }
# Accounts
app.get '/account/login', (req, res) ->
	res.render 'account/
	in', { title: "Login" }
app.get '/account/signup', (req, res) ->
	res.render 'account/signup', { title: "Signup" }
app.get '/api/logout', (req, res) ->
	res.redirect
# Error Pages
app.get '/404', (req, res) ->
	res.render 'index', { title: "404", user: req.session.user || null }

###
API routes
###
app.post '/api/login', (req, res) ->
	db.logins.findOne
		email: req.body.email
		(err, login) ->
			if err
				res.send "You're not signed up."
			else
				pwd.hash req.body.pass, login.salt, (err, hash) ->
					if login.hash is hash
						db.users.findOne
							email: login.email
							(err, user) ->
								req.session.user = user
								res.send "You logged in as #{user.email}! <a href='/'>Go back</a>"
					else
						res.send "Wrong password. <a href='/'>Go back</a>"

app.post '/api/signup', (req, res) ->
	db.logins.findOne 
		email: req.body.email
		(err, found) ->
			if found or req.body.pass is not req.body.passConfirm
				res.send 'You failed to sign up.'
			else
				pwd.hash req.body.pass, (err, salt, hash) ->
					db.logins.save
						email: req.body.email
						salt: salt
						hash: hash
				res.send "You signed up! <a href='/'>Go back</a>"

app.post '/api/logout', (req, res) ->
	req.session.destroy (err) ->
		if err
			console.log err
		res.send "Logged out! <a href='/'>Go back</a>"


###
Start listening.
###
app.listen 8080
console.log "GOV Listening on port 8080"