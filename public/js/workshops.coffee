$('a.edit').click ->
	id = $(this).data('id')
	$.post "/api/workshop/getEditForm?workshop=#{id}", (data) ->
		$('#workshop').html(data)

$('a.addWorkshop').click ->
	inputs = $('form#workshops')
	for input in inputs
		$(input).val('')
		
###
$('select.select2').select2
	allowclear: true
	placeholder: "Select members..."
###
