$('a.notes').click ->
	$.post '/api/getGroupNotes',
		id: $(this).data('id')
		(data) ->
			$('#groupNotes').html(data)