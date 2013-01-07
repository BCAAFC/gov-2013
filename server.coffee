# # server.coffee
# This is the main workhorse script for all serverside handlings. Try to keep this file clean and tidy, you can always spin off modules and pull them in with `foo = require 'foo'`.

# ## Pull in dependencies
# Since w're already using coffeescript to bootstrap the application, we don't need to pull it in.

# We'll pull in [Express](http://expressjs.com) which handles routing and generally makes life easier in a number of ways. Definately check out the API reference, it's gorgeously documented.
express = require 'express'

# Next we'll need to pull in [Mongoose](http://mongoosejs.com) which drives our [MongoDB](http://www.mongodb.org) connection.
mongoose = require 'mongoose'

# We will also need the excellent [Node-pwd](https://github.com/visionmedia/node-pwd)
pwd = require 'pwd'

# Connect-assets handles transparent compiling for us.
assets = require 'connect-assets'

# Setup the AppFog Enviroment. AppFog basically hands us a bunch of data in an enviroment variable called `VCAP_SERVICES`. [Appfog's Documentation](https://docs.appfog.com/services)
appfog = JSON.parse process.env.VCAP_SERVICES if process.env.VCAP_SERVICES?

# ## Set up the Database

# We need to figure out where we are hosted, and set up some information regarding that. You should replace the **bottom** case if you need changes to your local deveopment property.
if appfog
	mongo = env['mongodb-1.8'][0]['credentials']
else
	mongo =
		hostname: "localhost"
		port: 27017
		groupname: ""
		password: ""
		name: ""
		db: "gov"
# A function to create a connection URL. This was found in [Appfog's Mongodb Documentation](https://docs.appfog.com/services/mongodb).
generate_mongo_url = (obj) ->
	obj.hostname = (obj.hostname or "localhost")
	obj.port = (obj.port or 27017)
	obj.db = (obj.db or "govNext")
	if obj.groupname and obj.password
		"mongodb://" + obj.groupname + ":" + obj.password + "@" + obj.hostname + ":" + obj.port + "/" + obj.db
	else
		"mongodb://" + obj.hostname + ":" + obj.port + "/" + obj.db
# Now we can connect to our MongoDB server simply, regardless of where we're hosted.
db = mongoose.createConnection generate_mongo_url mongo
# We'll announce the state of the database connection to the console.
db.on 'error', console.error.bind(console, 'Connection error:')
db.once 'open', () ->
	console.log "Connection success: Database at #{mongo.hostname}:#{mongo.port}"

# ## App Resources

# [Mongoose](http://mongoosejs.com) provides us some amazing functionality in the form of schemas and models. We'll pull these from our `resources/models` file.
Models = require './resources/models'
Login = db.model 'Login', Models.loginSchema
Workshop = db.model 'Workshop', Models.workshopSchema
Group = db.model 'Group', Models.groupSchema
Member = db.model 'Member', Models.memberSchema

###
# Custom Functions
###
getTicketPrice = () ->
	today = new Date()
	deadline = new Date("Febuary 9, 2012 00:00:00")
	if (today <= deadline)
		return 175
	else
		return 125

# ## Configure Express

# The [Express API Documentation](http://expressjs.com/api.html) is extremely useful here.
server = express()
server.configure ->
	server.set "views", "#{__dirname}/views"
	server.set "view engine", "jade"
	# Avoid using `server.use express.compress()`, it screws up connect-assets
	# Use a favicon, however we don't expressly specify one yet.
	server.use express.favicon()
	server.use express.logger("dev")
	server.use express.bodyParser()
	server.use express.methodOverride()
	# Connect-assets
	server.use assets
			src: 'public'
	# You should set a proper cookie secret in your enviroment.
	server.use express.cookieParser(process.env.COOKIE_SECRET or 'test')
	# We store user sessions in memory. You should probably set a proper secret here as well.
	server.use express.session
		secret: process.env.SESSION_SECRET or 'test'
		store: new express.session.MemoryStore
	# It's very important that we use `server.router` before our 404 handler... Otherwise everything gets mapped to 404s.
	server.use server.router
	# Everything in the `/public` folder is mapped for easy access to styles and scripts.
	server.use express.static "#{__dirname}/public"
	server.use express.directory "#{__dirname}/public"
	# Our 404 handler.
	server.use (req, res) ->
		res.status 404
		res.send "You've hit a page which doesn't exist!"


###
GET routes
###
server.get '/', (req, res) ->
	res.render 'index',
		title: "Home"
		group: req.session.group || null

server.get '/privacy', (req, res) ->
	res.render 'privacy',
		title: "Privacy Policy"
		group: req.session.group || null

server.get '/account', (req, res) ->
	Group.findById(req.session.group._id).populate('groupMembers').exec (err, group) ->
		if err
			console.log err
			res.send "There was an error."
		else
			# Accumulate Bill and toss members into buckets for easy JADE-ing.
			req.session.group = group
			bill = 0
			youth = []
			youngAdults = []
			chaperones = []
			for member in group.groupMembers
				bill += member.ticketPrice
				if member.type is "Youth"
					youth.push member
				else if member.type is "Young Adult"
					youngAdults.push member
				else if member.type is "Chaperone"
					chaperones.push member
			# Temp workaround while we migrate to a better UI
			group.youth = youth
			group.youngAdults = youngAdults
			group.chaperones = chaperones
			req.session.group = group
			# Accumulate Paid
			paid = 0
			if req.session.group.payments
				for payment in req.session.group.payments
					paid += payment.amount
			res.render 'account/index',
				title: "Account Management"
				group: req.session.group || null
				billing:
					total: bill
					paid: paid

server.get '/account/signup', (req, res) ->
	res.render 'account/signup',
		title: "Signup"
		group: req.session.group || null
		
server.get '/admin', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.find {}, (err, groups) -> # Find all groups
			Workshop.find {}, (err, workshops) -> # Find all workshops
				res.render 'admin/index',
					title: "Administration"
					group: req.session.group || null
					groups: groups
					workshops: workshops

server.get '/admin/login/:id', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.params.id, (err, group) ->
			req.session.group = group
			res.redirect '/account'
			
server.get '/workshops/:day', (req, res) ->
	Workshop.find day: req.params.day, (err, workshops) ->
		if err
			res.send "There was an error fetching the workshops."
		else
			if req.session.group
				Group.findById(req.session.group._id).populate('groupMembers').exec (err, group) ->
					res.render 'workshops',
						title: '404'
						group: group || null
						workshops: workshops
			else
				res.render 'workshops',
					title: '404'
					group: null
					workshops: workshops

# Error Pages
server.get '/404', (req, res) ->
	res.render 'index',
		title: "404"
		group: req.session.group || null


###
API routes
###
server.post '/api/login', (req, res) ->
	Login.findOne email: req.body.email, (err, login) ->
		console.log 'Found login'
		if err or not login
			res.send "You're not signed up."
		else
			pwd.hash req.body.pass, login.salt, (err, hash) ->
				if login.hash is hash
					Group.findByIdAndUpdate login._group,
						$push: log: event: "This account was logged in with #{req.ip}"
						(err, group) ->
							req.session.group = group
							res.redirect '/'
				else
					res.send "Wrong password. <a href='/'>Go back</a>"

server.post '/api/signup', (req, res) ->
	# Fail if the form isn't filled out
	for item in ['name', 'email', 'pass', 'passConfirm', 'phone', 'affiliation', 'address', 'city', 'province', 'postalCode']
		if req.body[item] is "" or null
			res.send "Please be aware all fields (except fax) are required and must be filled out."
	
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
								Group.findByIdAndUpdate group._id,
									$push: log: event: 'This group account was created.',
									(err, group) ->
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

server.post '/api/logout', (req, res) ->
	Group.findByIdAndUpdate req.session.group._id,
		$push: log: event: "The account logged out from #{req.ip}"
		(err, group) ->
	req.session.destroy (err) ->
		if err
			res.send err
		else
			res.redirect "/"

###
Group API
###
server.post '/api/addMember', (req, res) ->
	# Fail if the name is empty
	if req.body.name is "" or null
		res.send "Please fill out a name (even a placeholder) for this member."
	req.body.ticketPrice = getTicketPrice()
	member = new Member req.body
	member.group = req.session.group._id
	member.save (err) ->
		if err
			res.send "We could not save that member, could you try again?"
		else
			Group.findByIdAndUpdate req.session.group._id,
				$push:
					groupMembers: member._id
					log: event: "The member #{req.body.name} was added to the group member list."
				(err, group) ->
					if err
						res.send "There was an error adding the member to your group."
					else
						req.session.group = group
						res.redirect '/account#members'

server.get '/api/removeMember/:type/:name/:id', (req, res) ->
	Group.findById req.session.group._id, (err, group) ->
		if err
			res.send "There was an error removing that member, could you try again?"
			console.log err
		else
			index = group.groupMembers.indexOf req.params.id
			group.groupMembers.splice index, 1
			group.save (err) ->
				if err
					res.send "We couldn't save your changes. try again?"
				else
					Member.findById req.params.id, (err, member) ->
						if err
							console.log err
							res.send "The user was removed from your group, but may still exist in our system. (There was an error)"
						else
							member.remove()
							console.log "#{member.name} removed!"
							req.session.group = group
							res.redirect '/account#members'
					
server.post '/api/editMember', (req, res) ->
	Member.findOne req.body.id, (err, member) ->
		member.name = req.body['member.name']
		member.birthDate = req.body['member.birthDate']
		member.gender = req.body['member.gender']
		member.phone = req.body['member.phone']
		member.email = req.body['member.email']
		member.emergencyInfo.medicalNum = req.body['member.emergencyInfo.medicalNum']
		member.emergencyInfo.allergies = req.body['member.emergencyInfo.allergies']
		member.emergencyInfo.conditions = req.body['member.emergencyInfo.conditions']
		member.emergencyInfo.name = req.body['member.emergencyInfo.name']
		member.emergencyInfo.relation = req.body['member.emergencyInfo.relation']
		member.emergencyInfo.phone = req.body['member.emergencyInfo.phone']
		member.save (err) ->
			if err
				res.send "The edits could not be saved. Please try again?"
			else
				Group.findByIdAndUpdate req.session.group._id,
					$push:
						log:
							event: "The member #{req.body['member.name']} was updated."
					(err, group) ->
						if err
							res.send "You're not logged in."
						else
							req.session.group = group
							res.redirect '/account#members'
									
server.post '/api/editGroup', (req, res) ->
	Group.findById req.session.group._id, (err, group) ->
		if err
			res.send "There was an error, could you try again?"
		else
			group.groupInformation.affiliation = req.body.affiliation
			group.groupInformation.address = req.body.address
			group.groupInformation.city = req.body.city
			group.groupInformation.province = req.body.province
			group.groupInformation.postalCode = req.body.postalCode
			group.groupInformation.fax = req.body.fax
			group.primaryContact.name = req.body.name
#			group.primaryContact.email = req.body.email		# This is bad! Don't do this!
			group.primaryContact.phone = req.body.phone
			group.save (err) ->
				if err
					res.send "There was an error, could you try again?"
				else
					Group.findByIdAndUpdate req.session.group._id,
						$push: log: event: "The group information was edited.",
						(err, result) ->
							req.session.group = group
							res.redirect '/account#groupinfo'


server.post '/api/getMember', (req, res) ->
	Member.findById req.body.id, (err, member) ->
		if err
			res.send "Could not find member."
		else
			res.render 'account/elements/memberInfo', member: member
		
###
Workshop API
###
server.post '/api/editWorkshop', (req,res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else if req.body.name is "" or req.body.day is ""
		res.send "You need to put a name and day in at least!"
	else if req.body.id is "new"
		workshop = new Workshop
			name: req.body.name
			host: req.body.host
			description: req.body.description
			timeStart: req.body.timeStart
			timeEnd: req.body.timeEnd
			room: req.body.room
			day: req.body.day
			capacity: req.body.capacity
			signedUp: []
		workshop.save (err, workshop) ->
			if err
				res.send "There was an error saving."
				console.log err
			else
				res.redirect "/workshops/#{req.body.day}"
	else
		Workshop.findById req.body.id, (err, workshop) ->
			if err
				res.send "There was an error editing that workshop."
			else
				workshop.name = req.body.name
				workshop.host = req.body.host
				workshop.description = req.body.description
				workshop.timeStart = req.body.timeStart
				workshop.timeEnd = req.body.timeEnd
				workshop.room = req.body.room
				workshop.day = req.body.day
				workshop.capacity = req.body.capacity
				workshop.save (err, workshop) ->
					if err
						res.send "There was an error saving."
					else
						res.redirect "/workshops/#{req.body.day}"
	
server.post '/api/getWorkshop', (req, res) ->
	Workshop.findById req.body.id, (err, result) ->
		if err
			res.send "No workshop found! Try again?"
		else
			res.render 'elements/workshop', workshop: result
			
server.get '/api/delWorkshop/:id', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Workshop.remove _id: req.params.id, (err, workshop) ->
			if err
				res.send "Couldn't remove that workshop! Try again?"
			else
				res.redirect "/workshops/#{workshop.day}"
				
server.get '/api/workshop/get', (req, res) ->
	Workshop.findById
	if req.query.workshop
		Workshop.findById req.query.workshop, (err, workshop) ->
			if err
				res.send "We couldn't get that workshop for you."
			else
				if req.query.group
					Group.findById(req.query.workshop).populate('groupMembers').exec (err, group)->
						if err
							res.send "We couldn't find your group!"
						else
							res.render 'workshopInfo',
								title: "Workshop Info"
								group: req.session.group || null
								workshop: workshop
				else
					res.render 'workshopInfo',
								title: "Workshop Info"
								group: null
								workshop: workshop
	else
		res.send "You need to ask for a workshop."

# Maybe Deprecate this
server.post '/api/workshop/changeMembers', (req, res) ->
	console.log req.body
	Group.findById(req.session.group._id).populate('groupMembers').exec (err, group) ->
		if err
			res.send "We couldn't find your group... Maybe there has been a mistake?"
		else
			Workshop.findById req.body.workshop, (err, workshop) ->
				if err
					res.send "We couldn't find that workshop... Maybe there has been a mistake?"
				else
					for member in req.body.attending
						# Do stuff
						console.log member
		
###
Group API
###
server.post '/api/getGroupNotes', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.body.id, (err, result) ->
			if err
				res.send "No group found! Try again?"
			else
				res.render 'admin/elements/groupNotes', group: result
			
server.post '/api/editGroupNotes', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.body.id, (err, result) ->
			if err
				res.send "Couldn't find that group!! Try again?"
			else
				result.internal.status = req.body.status
				result.internal.youthInCare = req.body.youthInCare
				result.internal.notes = req.body.notes
				result.save (err, result) ->
					if err
						res.send "Couldn't save those changes. Try again?"
					else
						res.redirect '/admin'
					
server.get '/api/removeGroup/:id', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.remove _id: req.params.id, (err) ->
			if err
				res.send "Couldn't remove that group! Try again?"
			else
				res.redirect '/admin'
				

###
Start listening.
###
server.listen process.env.VCAP_APP_PORT or 8080
console.log "Now listening..."