$('a.workshop').click ->
	$.post '/api/getWorkshop',
		id: $(this).data('id')
		(data) ->
			$('#workshop').html(data)