Documentation is forthcoming. Please excuse my negligance.

Usage notes:
To make a group an admin do something like so:
    db.groups.update({"primaryContact.email":"andrew@hoverbear.org"},{"$set":{"internal.admin":true}})