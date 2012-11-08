$('.member').click ->
	$.post '/api/getMember',
		id: $(this).data('id')
		type: $(this).data('type')
		(data) ->
			$('#memberInfo').html(data)