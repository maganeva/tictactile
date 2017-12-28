$(document).ready(function(){

	$("#MenuIcon").click(function(){
		console.log("asdf")
		$("#MainMenu").css("left","0px");
		function showMenu(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,100% 100%,0% 100%)");
			$("#MenuIcon").animate({right:'-100'},300);
		}
		setTimeout(showMenu,100);
	});

	$("#close").click(function(){
		$("#MainMenu").css("-webkit-clip-path","polygon(0 0,0% 0,100% 100%,0% 100%)");
		function hideMenu(){
			$("#MainMenu").css("left","-300px");
			$("#MenuIcon").animate({right:'50'},300);
		}
		setTimeout(hideMenu, 300);

		function originallayout(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,0% 100%,0% 100%)");
		}
		setTimeout(originallayout, 600);
	});




	$("li").click(function(){
		$("#MainMenu").css("-webkit-clip-path","polygon(0 0,0% 0,100% 100%,0% 100%)");
		function hideMenu(){
			$("#MainMenu").css("left","-300px");
			$("#MenuIcon").animate({right:'50'},300);
		}
		setTimeout(hideMenu, 300);

		function originallayout(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,0% 100%,0% 100%)");
		}
		setTimeout(originallayout, 600);
	});


	//modal onclick function
	function onClick(element) {
				document.getElementById("img01").src = element.src;
				document.getElementById("modal01").style.display = "block";
			}


	//Show modal with url
			
		// if(window.location.href.indexOf('#businesscenter') != -1) {
  //   	$("#businesscenter").show();
  // 	}

  // 	if(window.location.href.indexOf('#parametricexperiment') != -1) {
  	
  //   	$("#parametricexperiment").show();
  // 	}



 	//stop video when modal is clicked by reseting the source
    $('#modal033, #modal022, #modal0101, #modalvideo1, #modalvideo2, #modalvideo3').each(function(){
     	var src = $(this).find('video').find('source').attr('src');

      $(this).on('click', function(){
			$(this).find('video').attr('src', '');
      $(this).find('video').attr('src', src);
        });
    });

		
    // open modals if their id is in the url

		$('.wrapper').find('.w3-modal').each(function(){
			var id = $(this).attr('id');
	
			if(window.location.href.indexOf('#'+id) != -1) {
				console.log(window.location.href.indexOf('#'+id))
    	$('#'+id).show();
  	}
		
		});


		$(document).bind('scroll',function(e){
    	$('section').each(function(){
        if (
           $(this).offset().top < window.pageYOffset + 10
				//begins before top
        && $(this).offset().top + $(this).height() > window.pageYOffset + 10
				//but ends in visible area
				//+ 10 allows you to change hash before it hits the top border
        ) {
            window.location.hash = $(this).attr('id');
        }
    	});
		});


});