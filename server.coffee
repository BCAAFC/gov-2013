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

# We will use NodeMailer to send emails from the app.
nodemailer = require("nodemailer")
mailer = nodemailer.createTransport("SMTP",
		host: 'smtp.gmail.com',
		port: 465,
		ssl: true,
		use_authentication: true,
		user: process.env.mail_user,
		pass: process.env.mail_pass
)

# Setup the AppFog Enviroment. AppFog basically hands us a bunch of data in an enviroment variable called `VCAP_SERVICES`. [Appfog's Documentation](https://docs.appfog.com/services)
appfog = JSON.parse process.env.VCAP_SERVICES if process.env.VCAP_SERVICES?

# ## Set up the Database

# We need to figure out where we are hosted, and set up some information regarding that. You should replace the **bottom** case if you need changes to your local deveopment property.
if appfog
	mongo = appfog['mongodb-1.8'][0]['credentials']
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
Payment = db.model 'Payment', Models.paymentSchema

###
# Custom Functions
###
getTicketPrice = () ->
	today = new Date()
	deadline = new Date("Febuary 9, 2013 00:00:00")
	if (today <= deadline)
		console.log "Got 125"
		return 125
	else
		console.log "Got 175"
		return 175

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

# ## Useful Middleware
# TODO: Move to cookies
requireAuthentication = (req, res, next) ->
	if not req.session.group?
		res.send "This page requires authentication, please log in."
	else
		next()

# TODO: Move to cookies
populateGroupMembers = (req, res, next) ->
	if not req.session.group?
		next()
	else
		Group.findById(req.session.group._id).populate('groupMembers').populate('payments').exec (err, group) ->
			if err
				res.send "It looks like that group doesn't exist in our records. You might want to give us a call. \n #{err}"
			else
				req.group = group
				next()
				
# TODO: Move to cookies
populateGroup = (req, res, next) ->
	if not req.session.group?
		next()
	else
		Group.findById(req.session.group._id).exec (err, group) ->
			if err
				res.send "It looks like that group doesn't exist in our records. You might want to give us a call. \n #{err}"
			else
				req.group = group
				next()

# This method requires the workshop to be specified in the query. Eg. `/foo?workshop=foo` would result in `req.query.workshop = foo`
populateWorkshop = (req, res, next) ->
	if not req.query.workshop?
		next()
	else
		Workshop.findById req.query.workshop, (err, workshop) ->
			if err
				res.send "There was an error finding that workshop. \n #{err}"
			else
				req.workshop = workshop
				next()

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

server.get '/account', requireAuthentication, populateGroupMembers, (req, res) ->
	# Accumulate Bill and toss members into buckets for easy JADE-ing.
	group = req.group
	bill = 0
	youth = []
	youngAdults = []
	chaperones = []
	earlyTotal = 0
	regTotal = 0
	# Free tickets. For every 5 tickets they get a 6th free.
	# We need to split them because we don't want to give them extra free money.
	freeEarly = 0
	freeReg = 0
			
	for member in group.groupMembers
		bill += member.ticketPrice
				
		if member.ticketPrice is 125
			earlyTotal += 1
		else if member.ticketPrice is 175
			regTotal += 1
				
		if member.type is "Youth"
			youth.push member
		else if member.type is "Young Adult"
			youngAdults.push member
		else if member.type is "Chaperone"
			chaperones.push member
	
	# Calculate number of free tickets allowed.
	freeTickets = Math.floor( (earlyTotal / 5) + (regTotal / 5) )
	
	# Calculate the number of free regular priced tickets
	freeReg = Math.floor( regTotal / 6 )
	freeEarly = Math.floor ( earlyTotal / 6 )
	
	# If we have extra free Regulars
	if (freeTickets - freeReg - freeEarly) > 1 and regTotal > 0
		freeReg++
	
	# Accumulate the amounts paid.
	earlyPaid = 0
	regPaid = 0
	for payment in group.payments
		earlyPaid += payment.earlyTickets
		regPaid += payment.regTickets
					
	# Temp workaround while we migrate to a better UI
	group.youth = youth
	group.youngAdults = youngAdults
	group.chaperones = chaperones
	req.session.group = group
			
	res.render 'account/index',
		title: "Account Management"
		group: req.session.group || null
		billing:
			total: bill - (freeEarly * 125) - (freeReg * 175)
			earlyTotal: earlyTotal
			regTotal: regTotal
			freeEarly: freeEarly
			freeReg: freeReg
			earlyPaid: earlyPaid
			regPaid: regPaid

server.get '/account/signup', (req, res) ->
	res.render 'account/signup',
		title: "Signup"
		group: req.session.group || null
		
server.get '/account/startRecovery', (req, res) ->
	res.render 'account/startRecovery',
		title: "Password Recovery"
		group: null

server.post '/account/startRecovery', (req, res) ->
	if req.body.skill is '10'
		Group.findOne 'primaryContact.email': req.body.email, (err, group) ->
			if err
				res.send "We couldn't find a group associated with that email... Maybe you used a different email?"
			else
				mailer.sendMail
					from: "gatheringourvoices.noreply@gmail.com"
					to: group.primaryContact.email
					subject: "Gathering Our Voices 2013 -- Password Recovery"
					html: "Hello! There was a request to recover your password via the Gathering Our Voices 2013 site. If this was you, please visit <a href='http://gatheringourvoices.bcaafc.com/account/endRecovery?key=#{group._id}&email=#{group.primaryContact.email}'>this link.</a>"
					(err)->
						if err
							res.send "We couldn't mail you a recovery email... Call us at 250-388-5522"
						else
							res.send "We've sent you a recovery email... Please check your email."
	else
		res.send "It looks like you might be a robot... If you're having trouble with answering the question try entering '10'."

# Requires a '?key=foo&email=bar' where key should be equal to the group ID.
server.get '/account/endRecovery', (req, res) ->
	res.render 'account/endRecovery',
		title: "Password Recovery"
		group: null
		key: req.query.key || null
		email: req.query.email || null

server.post '/account/endRecovery', (req, res) ->
	if req.body.pass is not req.body.passConfirm
		res.send "Please make sure your passwords match!"
	else
		Login.findOne email: req.body.email, _group: req.body.key, (err, login) ->
			if (err) or (login is null)
				res.send "We couldn't find that group."
			else
				pwd.hash req.body.pass, (err, salt, hash) ->
					if err
						res.send "There was a problem hashing your password."
					else
						login.salt = salt
						login.hash = hash
						login.save (err) ->
							if err
								res.send "There was a problem saving your new password."
							else
								res.send "Password recovered successfully, please return <a href='http://gatheringourvoices.bcaafc.com'>home</a> and try to login!"

		
server.get '/admin', requireAuthentication, (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.find({}).sort('groupInformation.affiliation').exec (err, groups) -> # Find all groups
			Workshop.find {}, (err, workshops) -> # Find all workshops
				totals =
					members: 0
					workshops: workshops.length
				for group in groups
					totals.members += group.groupMembers.length
				res.render 'admin/index',
					title: "Administration"
					group: req.session.group || null
					groups: groups
					workshops: workshops
					totals: totals

# This route requires a '?group=foo' query where foo is the group id.
server.get '/admin/payments', requireAuthentication, (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById(req.query.group).populate('payments').exec (err, targetGroup) ->
			if err
				res.send "We couldn't find that group."
			else
				# Sum the totals
				totalEarly = 0
				totalReg = 0
				for payment in targetGroup.payments
					totalEarly += payment.earlyTickets
					totalReg += payment.regTickets

				res.render 'admin/payments',
					title: "Administration - Payments for group"
					group: req.session.group || null
					targetGroup: targetGroup
					totals:
						early: totalEarly
						reg: totalReg
			

# Requires a query: "/admin/log?group=foo"
server.get '/admin/log', requireAuthentication, (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.query.group, (err, targetGroup) ->
			if err
				res.send "We couldn't get that group."
			else
				res.render 'admin/log',
					title: "Administration - Log"
					group: req.session.group || null
					targetGroup: targetGroup

server.get '/admin/login/:id', requireAuthentication, (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.params.id, (err, group) ->
			req.session.group = group
			res.redirect '/account'

server.get '/workshopHome', (req, res) ->
	res.render 'workshopHome'
		title: "Workshop"
		group: req.session.group || null
			
server.get '/workshops/:day', (req, res) ->
	if req.params.day == 'wednesday'
		day = 'March 20, 2013'
	else
		day = 'March 21, 2013'
	Workshop.find(day: day).sort('timeStart').exec (err, workshops) ->
		if err
			res.send "There was an error fetching the workshops."
		else
			if req.params.day is "wednesday"
				day = "Wednesday"
			else
				day = "Thursday"
			if req.session.group
				Group.findById(req.session.group._id).populate('groupMembers').exec (err, group) ->
					res.render 'workshopList',
						title: 'Workshops'
						group: group || null
						workshops: workshops
						day: day
			else
				res.render 'workshopList',
					title: 'Workshops'
					group: null
					workshops: workshops
					day: day

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
		if err or not login
			res.send "You're not signed up."
		else
			pwd.hash req.body.pass, login.salt, (err, hash) ->
				if login.hash is hash
					Group.findByIdAndUpdate login._group,
						$push: log: event: "LOGIN: From #{req.ip}"
						(err, group) ->
							req.session.group = group
							res.redirect '/'
				else
					res.send "Wrong password. <a href='/'>Go back</a>"

server.post '/api/signup', (req, res) ->
	# Fail if the form isn't filled out
	isOk = true
	for item in ['name', 'email', 'pass', 'passConfirm', 'phone', 'affiliation', 'address', 'city', 'province', 'postalCode']
		if req.body[item] is "" or null
			isOk = false
			res.send "Please be aware all fields (except fax) are required and must be filled out."
	if isOk
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
										$push: log: event: 'CREATION: Group was created',
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
													mailer.sendMail
														from: "gatheringourvoices.noreply@gmail.com"
														to: group.primaryContact.email
														bcc: "gatheringourvoices@bcaafc.com, dpreston@bcaafc.com"
														subject: "Gathering Our Voices 2013 -- Registration Successful!"
														html: "<h1>Hello #{group.primaryContact.name} of the #{group.groupInformation.affiliation}</h1>
															<h3>Thank you for submitting your online registration!</h3>
															<p>The Gathering Our Voices team will review your registration and send you an email response which can include the following:</p>
															<ol>
																<li>Request for missing information</li>
																<li>Payment arrangements</li>
																<li>Confirmation of official registration</li>
															</ol>
															<h3>Workshop Registration</h3>
															<p>Workshop Registration will be available mid-February. You will receive and e-mail when workshop registration is open.</p>
															<p>If you have any questions or concerns please contact:</p>
															<p>Siku Allooloo, Conference Registration Coordinator</p>
															<p>Email: <a href='mailto:gatheringourvoices@bcaafc.com'>gatheringourvoices@bcaafc.com</a></p>
															<p>Phone: (250) 388-5522 or toll-free: 1-800-990-2432</p>"
														(err)->
															if err
																res.send "We couldn't mail you a registration confirmation email... Call us at 250-388-5522"
															else
																res.redirect '/'

server.post '/api/logout', (req, res) ->
	Group.findByIdAndUpdate req.session.group._id,
		$push: log: event: "LOGOUT: From #{req.ip}"
		(err, group) ->
	req.session.destroy (err) ->
		if err
			res.send err
		else
			res.redirect "/"

###
Group API
###
server.post '/api/addMember', requireAuthentication, (req, res) ->
	# Fail if the name is empty
	if req.body.name is "" or null
		res.send "Please fill out a name (even a placeholder) for this member."
	else if req.body.type is "" or null
		res.send "You need to specify a type for that attendee (Youth, Young Adult, or Chaperone)"
	else
		req.body.ticketPrice = getTicketPrice()
		member = new Member req.body
		member.group = req.session.group._id
		member.regDate = new Date()
		member.save (err) ->
			if err
				res.send "We could not save that member, could you try again?"
				console.log err
			else
				Group.findByIdAndUpdate req.session.group._id,
					$push:
						groupMembers: member._id
						log: event: "MEMBER ADD: #{req.body.name} (#{member._id}) was added."
					$set:
						'internal.status': "Edited - Unchecked"
					(err, group) ->
						if err
							res.send "There was an error adding the member to your group."
						else
							req.session.group = group
							res.redirect '/account#members'

server.get '/api/removeMember/:type/:name/:id', requireAuthentication, (req, res) ->
	Group.findById req.session.group._id, (err, group) ->
		if err
			res.send "There was an error removing that member, could you try again?"
			console.log err
		else
			index = group.groupMembers.indexOf req.params.id
			group.groupMembers.splice index, 1
			group.internal.status = "Edited - Unchecked"
			group.log.push {date: new Date(), event: "MEMBER REMOVE: #{req.body.name} (#{req.body.id}) was removed."}
			group.save (err) ->
				if err
					res.send "We couldn't save your changes. try again?"
				else
					Member.findById req.params.id, (err, member) ->
						if err or member is null
							console.log err
							res.send "The user was removed from your group, but may still exist in our system. (There was an error)"
						else
							for workshopId in member.workshops
								Workshop.findById workshopId, (err, workshop) ->
									if err or workshop is null
										console.log "Couldn't remove #{req.params.id} from #{workshopId}: \n #{err}"
									else
										index = workshop.signedUp.indexOf req.params.id
										workshop.signedUp.splice index, 1
										console.log "Removed #{req.params.id} from #{workshop._id}"
										workshop.save()
							member.remove()
							req.session.group = group
							res.redirect '/account#members'
					
server.post '/api/editMember', requireAuthentication, (req, res) ->
	Member.findById req.body.id, (err, member) ->
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
		member.youthInCare = req.body['youthInCare']
		member.save (err) ->
			if err
				res.send "The edits could not be saved. Please try again?"
			else
				# A neccessary evil.
				Group.findByIdAndUpdate req.session.group._id,
					$set:
						'internal.status': "Edited - Unchecked"
					$push:
						log:
							event: "MEMBER UPDATE: #{req.body['member.name']} (#{member._id}) was updated."
					(err) ->
						if err
							console.log err
				res.redirect '/account#members'

server.post '/api/editGroup', requireAuthentication, (req, res) ->
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
			# Side effects
			group.log.push {date: new Date(), event: "GROUP EDIT: Info updated."}
			group.internal.status = "Edited - Unchecked"
			group.save (err) ->
				if err
					res.send "There was an error, could you try again?"
				else
					req.session.group = group
					res.redirect '/account#groupinfo'
							
server.post '/api/account/paymentType', requireAuthentication, (req, res) ->
	Group.findById req.session.group._id, (err, group) ->
		group.groupInformation.paymentType = req.body.paymentType
		group.internal.status = "Edited - Unchecked"
		group.log.push {date: new Date(), event: "NOTES: Group payment type updated."}
		group.save (err) ->
			if err
				res.send "There was a problem saving your payment type... Could you try again?"
			else
				res.redirect '/account#billing'


server.post '/api/getMember', requireAuthentication, (req, res) ->
	Member.findById(req.body.id).populate('workshops').exec (err, member) ->
		if err
			res.send "Could not find member."
		else
			res.render 'account/elements/memberInfo', 
				group: req.session.group
				member: member
		
###
Workshop API
###
server.post '/api/editWorkshop', requireAuthentication, (req,res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		# Build Valid Times
		timeStart = new Date "#{req.body.day} #{req.body.timeStart}"
		timeEnd = new Date "#{req.body.day} #{req.body.timeEnd}"
	
		if not req.session.group.internal.admin # If --not-- admin
			res.send "You're not authorized, please don't try again!"
		else if req.body.name is "" or req.body.day is ""
			res.send "You need to put a name and day in at least!"
		else if req.body.id is "new"
			workshop = new Workshop
				name: req.body.name
				host: req.body.host
				description: req.body.description
				timeStart: timeStart
				timeEnd: timeEnd
				session: req.body.session
				room: req.body.room
				day: req.body.day
				capacity: req.body.capacity
				signedUp: []
			workshop.save (err, workshop) ->
				if err
					res.send "There was an error saving."
					console.log err
				else
					if req.body.day is 'March 20, 2013'
						target = 'wednesday'
					else
						target = 'thursday'
					res.redirect "/workshops/#{target}"
		else
			Workshop.findById req.body.id, (err, workshop) ->
				if err or workshop is null
					res.send "There was an error editing that workshop."
				else
					workshop.name = req.body.name
					workshop.host = req.body.host
					workshop.description = req.body.description
					workshop.timeStart = timeStart
					workshop.timeEnd = timeEnd
					workshop.session = req.body.session
					workshop.room = req.body.room
					workshop.day = req.body.day
					workshop.capacity = req.body.capacity
					workshop.save (err, workshop) ->
						if err
							res.send "There was an error saving."
						else
							if req.body.day is 'March 20, 2013'
								target = 'wednesday'
							else
								target = 'thursday'
							res.redirect "/workshops/#{target}"
	
server.post '/api/workshop/getEditForm', requireAuthentication, populateWorkshop, (req, res) ->
	res.render 'elements/workshop', workshop: req.workshop
			
# Requires a "?workshop=foo" query.
server.get '/api/workshop/delete', requireAuthentication, (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Workshop.findById req.query.workshop, (err, workshop) ->
			if err
				res.send "Couldn't remove that workshop! Try again?"
			else
				Member.find workshops: workshop._id, (err, members) ->
					for member in members
						index = member.workshops.indexOf workshop._id
						member.workshops.splice index, 1
					workshop.remove()
					res.redirect "/workshops/#{workshop.day}"

# Requires a "?workshop=foo" query.
server.get '/api/workshop/get', populateGroupMembers, populateWorkshop, (req, res) ->
	if req.group
		req.group.groupMembers.sort (a, b) ->
			if a.type > b.type
				return -1
			else if a.type < b.type
				return 1
			else
				return 0
	if not req.workshop
		res.send "We could not get the data for your workshop."
	else
		res.render 'workshopInfo',
			title: "Workshop Info"
			group: req.group || null
			workshop: req.workshop

# Requires a "?workshop=foo&member=bar" query.
server.get '/api/workshop/attendees/add', requireAuthentication, populateGroup, populateWorkshop, (req, res) ->
	if not req.workshop
		res.send "We could not get the data for your workshop."
	else if not req.query.member
		res.send "You did not specify a member."
	else if req.group.groupMembers.indexOf(req.query.member) is -1
		res.send "That member is not a part of your group... Perhaps you're lost?"
	else
		# Add workshop to the member
		Member.findById req.query.member, (err, member)->
			if err
				res.send "We couldn't find your member."
			else
				# Is the member already in that workshop?
				if member.workshops.indexOf(req.workshop._id) is -1
					# Is the workshop full already?
					if req.workshop.signedUp.length < req.workshop.capacity
						member.workshops.push req.workshop._id
						member.save (err)->
							if err
								res.send "We couldn't add that workshop to the member!"
							else
								# Add member to workshop
								req.workshop.signedUp.push member._id
								req.workshop.save (err)->
									if err
										res.send "There was an error adding that member to the workshop!"
									else
										Group.findByIdAndUpdate req.group._id,
											$push:
												log:
													event: "WORKSHOP: #{member.name} (#{member._id}) ADDED TO #{req.workshop.name} (#{req.workshop._id})."
											(err) ->
												if err
													console.log err
										res.redirect "/api/workshop/get?workshop=#{req.workshop._id}"
					else
						res.send "That workshop is full. Please find a different workshop."
				else
					res.send "That member is already a part of that workshop!"

# Requires a "?workshop=foo&member=bar" query.
server.get '/api/workshop/attendees/remove', requireAuthentication, populateGroup, populateWorkshop, (req, res) ->
	if not req.workshop
		res.send "We could not get the data for your workshop."
	else if not req.query.member
		res.send "You did not specify a member."
	else if req.group.groupMembers.indexOf(req.query.member) is -1
		res.send "That member is not a part of your group... Perhaps you're lost?"
	else
		# Remove workshop from member
		Member.findById req.query.member, (err, member)->
			if err
				res.send "We couldn't find your member."
			else
				if member.workshops.indexOf(req.workshop._id) is -1
					res.send "That member is not part of the given workshop."
				else
					member.workshops.splice member.workshops.indexOf(req.workshop._id), 1
					member.save (err)->
						if err
							res.send "We couldn't remove that workshop from the member!"
						else
							# Remove member from workshop
							req.workshop.signedUp.splice req.workshop.signedUp.indexOf(member._id), 1
							req.workshop.save (err)->
								if err
									res.send "There was an error removing that member from the workshop!"
								else
									Group.findByIdAndUpdate req.group._id,
										$push:
											log:
												event: "WORKSHOP: #{member.name} (#{member._id}) REMOVED FROM #{req.workshop.name} (#{req.workshop._id})."
										(err) ->
											if err
												console.log err
									res.redirect "/api/workshop/get?workshop=#{req.workshop._id}"


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
				result.internal.workshopReg = req.body.workshopReg
				result.internal.paymentStatus = req.body.paymentStatus
				result.groupInformation.paymentType = req.body.paymentType
				result.save (err, result) ->
					if err
						res.send "Couldn't save those changes. Try again?"
					else
						Group.findByIdAndUpdate req.body.id,
							$push:
								log:
									event: "NOTES: The group notes were edited."
							(err) ->
								if err
									console.log err
						res.redirect '/admin'

					
server.get '/api/removeGroup/:id', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		# Remove all members from the group first.
		Group.findById req.params.id, (err, group) ->
			if err
				res.send "Couldn't find that group!"
			else
				Login.remove _group: group._id, (err) ->
					if err
						console.log "Couldn't remove that login! #{err}"
				for member in group.groupMembers
					Member.findById member, (err, member) ->
						for workshopId in member.workshops
							Workshop.findById workshopId, (err, workshop) ->
								if err
									console.log "Couldn't remove #{req.params.id} from #{workshop._id}: \n #{err}"
								else
									index = workshop.signedUp.indexOf req.params.id
									workshop.signedUp.splice index, 1
									console.log "Removed #{req.params.id} from #{workshop._id}"
									workshop.save()
				Group.remove _id: req.params.id, (err) ->
					if err
						res.send "Couldn't remove that group! Try again?"
					else
						res.redirect '/admin'
				
###
Payments API
###
server.post '/api/payment/add', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.body.id, (err, group) ->
			payment = new Payment
				date: req.body.date
				earlyTickets: req.body.earlyTickets
				regTickets: req.body.regTickets
				paypal: req.body.paypal
				group: req.body.id
			payment.save (err) ->
				if err
					res.send "We couldn't save that payment."
				else
					group.payments.push payment._id
					group.save (err) ->
						if err
							res.send "We couldn't save the pay`ment to the group, but we did save the payment. How strange."
						else
							Group.findByIdAndUpdate group._id,
								$push:
									log:
										event: "PAYMENT: A payment was added (#{payment._id})."
								(err) ->
									if err
										console.log err
							res.redirect "/admin/payments?group=#{group._id}"

# Requires a query: "/api/payment/delete?group=bar&payment=foo"
server.get '/api/payment/delete', (req, res) ->
	if not req.session.group.internal.admin # If --not-- admin
		res.send "You're not authorized, please don't try again!"
	else
		Group.findById req.query.group, (err, group) ->
			payment = group.payments.indexOf req.query.payment
			group.payments.splice payment, 1
			group.save (err) ->
				if err
					res.send "We couldn't delete the payment from the group!"
				else
					Payment.remove "_id": req.query.payment, (err) ->
						if err
							res.send "We couldn't remove that payment."
						else
							Group.findByIdAndUpdate group._id,
								$push:
									log:
										event: "PAYMENT: A payment was removed (#{req.query.payment})."
								(err) ->
									if err
										console.log err
							res.redirect "/admin/payments?group=#{req.query.group}"

###
Start listening.
###
server.listen process.env.VCAP_APP_PORT or 8080
console.log "Now listening..."