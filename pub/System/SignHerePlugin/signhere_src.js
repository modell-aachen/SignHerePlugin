jQuery(function($) {
    $('form.signherebutton').submit(function() {
        var form = $(this);
        var btn = form.find('.jqButton');
        var btnSpan = btn.find('span');
        var sel = form.find('select');

        if (sel.val() == '') {
            alert(foswiki.signhere_l10n.choose_first);
            return false;
        }

        btnSpan.data('label', btnSpan.html());
        btnSpan.html('<img src="'+foswiki.getPreference('PUBURLPATH')+'/System/DocumentGraphics/processing-bg.gif" style="padding:3px;">');

        var restore = function() {
            btnSpan.html(btnSpan.data('label'));
            btnSpan.removeData('label');
            sel.removeAttr('disabled');
        }
        var data = form.serialize();
        sel.attr('disabled', 'disabled');

        $.ajax({
            'url': foswiki.getPreference('SCRIPTURLPATH')+'/rest'+foswiki.getPreference('SCRIPTSUFFIX')+'/SignHerePlugin/submit',
            'data': data,
            'dataType': 'json',
            'type': 'POST'
        }).done(function(data, textStatus, xhr) {
            if (data.status == 'error') {
                if (data.code == 'forbidden') {
                    alert(foswiki.signhere_l10n.error_forbidden);
                    return restore();
                } else if (data.status == 'locked') {
                    alert(foswiki.signhere_l10n.error_locked);
                    return restore();
                }
                alert(foswiki.signhere_l10n.error_invalid);
                return restore();
            }
            btnSpan.data('label', data.label);
            restore();
        })
        .fail(function(xhr, textStatus, errorThrown) {
            alert(foswiki.signhere_l10n.error_xhr + errorThrown);
            return restore();
        });
        return false;
    });
});
