$('a.workshop').click ->
	$.post '/api/getWorkshop',
		id: $(this).data('id')
		(data) ->
			$('#workshop').html(data)
			
$('a.notes').click ->
	$.post '/api/getGroupNotes',
		id: $(this).data('id')
		(data) ->
			$('#groupNotes').html(data)