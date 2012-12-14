$('a.edit').click ->
	$.post '/api/getWorkshop',
		id: $(this).data('id')
		(data) ->
			$('#workshop').html(data)

$('a.addWorkshop').click ->
	inputs = $('form#workshops')
	console.log inputs
	for input in inputs
		$(input).val('')