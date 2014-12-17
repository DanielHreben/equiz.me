function start_watching_answers() {
    $('studentanswerfield')    
    var names = find_all_questions_names();
    for ( var i=0; i < names.length; i++ ) {
        var $input = $('input[name="' + names[i] +  '"]');
        if ($input.is(':checkbox') || $input.is(':radio')) {
            $input.change(update_counter);
        } else {
            $input.keyup(update_counter);
        }
    }
    
    $('form.quizform').submit(function () {
        if ( $('input[name=allowpartial]').val() == 1 ? true : false ) {
            return true;
        }
        var count = count_non_answered_questions();
        
        if ( count ) { return false; }
        
        return true
    });
    
    update_counter();
}

function update_counter() {
    var count = count_non_answered_questions();
    var $submit_btn = $('input.quizsubmitbutton');
    var is_allow_partial = $('input[name=allowpartial]').val() == 1 ? true : false;
    
    
    if ( !update_counter.original_text ) {
        update_counter.original_text = $submit_btn.val();
    }
    
    var orig_text = update_counter.original_text;
    
    if (!is_allow_partial ) {
        if (count) {
            $submit_btn.prop('disabled', true);
        } else {
            $submit_btn.prop('disabled', false);
        }
    }
    
    $submit_btn.val(orig_text + count2str(count));
}


function count_non_answered_questions() {
    var names = find_all_questions_names();
    var questions_left = 0;
    
    for ( var i=0; i < names.length; i++ ) {
        if ( ! is_question_answered( names[i] ) ) {
            questions_left++;
        }
    }
    
    return questions_left;
}

function find_all_questions_names() {
    if (find_all_questions_names.names) {
        // get from cache
        return find_all_questions_names.names;
    }
    
    var names = [];
    var uniq_names = {};

    $('input.studentanswerfield, input.studentanswerfieldm').each(function() {
        var $this = $(this);
        uniq_names[$this.attr('name')] = 1;
    })
    
    for (var name in uniq_names) {
        names.push(name);
    }
    
    find_all_questions_names.names = names; // cache

    return names;
}

function is_question_answered(name) {
    var is_answered = 0;
    var $input = $('input[name="' + name +  '"]');
    
    if ($input.is(':checkbox') || $input.is(':radio')) {
        return $input.filter(':checked').size() ? 1 : 0;
    } else {
        return $input.val() ? 1 : 0;
    }
    
    return 0;
}

function count2str(count) {
    if ( count == 1 ) {
        return " (1 Question Left to To Answer)";
    } else if ( count > 1 ) {
        return " (" + count +" Questions Left to To Answer)";
    } else {
        return "";
    }
}
