# # models.coffee
# This file contains schema definitions for [Mongoose](http://mongoosejs.com). Make sure to check out the [Schema Docs](http://mongoosejs.com/docs/guide.html).

# First we need to require Mongoose, as well as anything else we might use.
mongoose = require 'mongoose'
Schema = mongoose.Schema
# Mongoose uses some strangly formatted ObjectId.
ObjectId = Schema.Types.ObjectId

# ## Schema & Models

###
Mongoose Schemas
###
exports.loginSchema = new Schema
	email: String
	salt: String
	hash: String
	_group: Schema.Types.ObjectId

exports.logSchema = new Schema
	date:
		type: Date
		default: Date.now
	event: String

exports.groupSchema = new Schema
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
	log: [exports.logSchema]
	payments: [
		type: Schema.Types.ObjectId
		ref: "Payment"
	]
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

exports.paymentSchema = new Schema
	date: Date
	amount: Number
	id: String # Points to Paypal's Unique Transaction ID
	group:
		type: Schema.Types.ObjectId
		ref: "Group"
		

# Members exist as part of groups, and are associated with groups.
exports.memberSchema = new Schema
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
	group:
		type: Schema.Types.ObjectId
		ref: "Group"

exports.workshopSchema = new Schema
	name: String
	host: String
	description: String
	timeStart: Date
	timeEnd: Date
	day: String
	room: String
	capacity: Number
	signedUp: [
		type: Schema.Types.ObjectId
		ref: 'Member'
	] # Points to Member