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


memberSchema = new Schema
	name: String
	type: String
	gender: String
	birthDate: String
	phone: String
	email: String
	emergencyInfo:
		name: String
		relation: String
		phone: String
		medicalNum: String
		allergies: [String]
		conditions: [String]
	ticketPrice: Number
	workshops: [
		type: Schema.Types.ObjectId
		ref: "Workshop"
	]
	group:
		type: Schema.Types.ObjectId
		ref: "Group"

logSchema = new Schema
	date:
		type: Date
		default: Date.now
	event: String

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
	groupMembers: [
		type: Schema.Types.ObjectId
		ref: "Member"
	] # Points to Member
	log: [logSchema]
	payments: [Schema.Types.ObjectId]
	internal:
		regDate:
			type: Date
			default: Date.now
		status: String
		youthInCare: String
		notes: String
		admin: 
			type: Boolean
			default: false
Group = db.model 'Group', groupSchema

# Members exist as part of groups, and are associated with groups.
memberSchema = new Schema
	name: String
	# Youth, Young Adult, or Chaperone
	type: String
	gender: String
	birthDate: String
	phone: String
	email: String
	emergencyInfo:
		name: String
		relation: String
		phone: String
		medicalNum: String
		# Ideally we will split the items listed in the future.
		allergies: String
		conditions: String
	ticketPrice: Number
	# These associate to `Workshop`s
	workshops: [
		type: Schema.Types.ObjectId
		ref: "Workshop"
	]
Member = db.model 'Member', memberSchema

workshopSchema = new Schema
	name: String
	host: String
	description: String
	day: String
	timeStart: String
	timeEnd: String
	room: String
	capacity: Number
	signedUp: [Schema.Types.ObjectId] # Points to Member
Workshop = db.model 'Workshop', workshopSchema

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
	Group.findById(req.session.group._id).populate('groupMembers').exec (err, group) ->
		# Accumulate Bill and toss members into buckets for easy JADE-ing.
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

app.get '/account/signup', (req, res) ->
	res.render 'account/signup',
		title: "Signup"
		group: req.session.group || null
		
app.get '/admin', (req, res) ->
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

app.get '/admin/login/:id', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.params.id, (err, group) ->
			req.session.group = group
			res.redirect '/account'
			
app.get '/workshops/:day', (req, res) ->
	Workshop.find day: req.params.day, (err, workshops) ->
		res.render 'workshops',
			title: '404'
			group: req.session.group || null
			workshops: workshops

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
						Group.findByIdAndUpdate login._group,
							$push: log: event: "This account was logged in with #{req.ip}"
							(err, group) ->
								req.session.group = group
								res.redirect '/'
					else
						res.send "Wrong password. <a href='/'>Go back</a>"

app.post '/api/signup', (req, res) ->
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

app.post '/api/logout', (req, res) ->
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
app.post '/api/addMember', (req, res) ->
	# Fail if the name is empty
	if req.body.name is "" or null
		res.send "Please fill out a name (even a placeholder) for this member."
	req.body.ticketPrice = getTicketPrice()
	member = new Member req.body
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

app.get '/api/removeMember/:type/:name/:id', (req, res) ->
	Group.findByIdAndUpdate req.session.group._id,
		$pull:
			groupMembers: req.params.id
		$push:
			log: event: "The member #{req.params.name} was removed from the group member list."
		(err, group) ->
			if err
				res.send "There was an error removing that member, could you try again?"
			else
				Member.remove req.params.id, (err) ->
					console.log "#{member.name} removed!"
					req.session.group = group
					res.redirect '/account#members'
					
app.post '/api/editMember', (req, res) ->
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
									
app.post '/api/editGroup', (req, res) ->
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


app.post '/api/getMember', (req, res) ->
	Member.findById req.body.id, (err, member) ->
		if err
			res.send "Could not find member."
		else
			res.render 'account/elements/memberInfo', member: member
		
###
Workshop API
###
app.post '/api/editWorkshop', (req,res) ->
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
	
app.post '/api/getWorkshop', (req, res) ->
	Workshop.findById req.body.id, (err, result) ->
		if err
			res.send "No workshop found! Try again?"
		else
			res.render 'elements/workshop', workshop: result
			
app.get '/api/delWorkshop/:id', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Workshop.remove _id: req.params.id, (err, workshop) ->
			if err
				res.send "Couldn't remove that workshop! Try again?"
			else
				res.redirect "/workshops/#{workshop.day}"
		
###
Group API
###
app.post '/api/getGroupNotes', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.body.id, (err, result) ->
			if err
				res.send "No group found! Try again?"
			else
				res.render 'admin/elements/groupNotes', group: result
			
app.post '/api/editGroupNotes', (req, res) ->
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
					
app.get '/api/removeGroup/:id', (req, res) ->
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
app.listen process.env.VCAP_APP_PORT or 8080
console.log "Now listening..."