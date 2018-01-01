$(document).ready(function(){

	window.showMenuSidebar = function () {
		$("#MainMenu").css("left","0px");
		function showMenu(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,100% 100%,0% 100%)");
			$("#MenuIcon").animate({right:'-100'},300);
		}
		setTimeout(showMenu,100);
	}

	$("#MenuIcon").click(window.showMenuSidebar);

	$("#home").click(window.showMenuSidebar);

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



	//Show modal with url

		// if(window.location.href.indexOf('#businesscenter') != -1) {
  //   	$("#businesscenter").show();
  // 	}

 	//stop video when modal is clicked by reseting the source

 	// window.itemRegex = /(?:\/i\/[^/]*)/
 	// window.sectionRegex = /(?:\/s\/[^/]*)/
 	// window.anchorParts = function (locationHash) {
 	// 	var itemMatch = itemRegex.exec(locationHash);
 	// 	var sectionMatch = sectionRegex.exec(locationHash);
 	// 	var anchorParts = {
 	// 		"section": null,
 	// 		"item": null
 	// 	};
 	// 	if (sectionMatch != null) {
 	// 		anchorParts["section"] = sectionMatch[0];
 	// 	}
 	// 	if (itemMatch != null) {
 	// 		anchorParts["item"] = itemMatch[0];
 	// 	}
 	// 	return anchorParts;
 	// }

 	// window.anchor = function (section, item) {
 	// 	var anchor = "#";
 	// 	if (section != null) {
 	// 		anchor += "/s/" + section;
 	// 	}
 	// 	if (item != null) {
 	// 		anchor += "/i/" + item;
 	// 	}
 	// 	return anchor;
 	// }

 	window.anchorParts = function (locationHash) {
 		var locationHashParts = locationHash.split('#');
 		var anchorParts = {
 			"section": null,
 			"item": null
 		};
 		if (locationHashParts.length > 1) {
 			locationHashParts = locationHashParts[1].split("/s/");
 		}
 		if (locationHashParts.length > 1) {
 			locationHashParts = locationHashParts[1].split("/i/");
 			anchorParts["section"]=locationHashParts[0]
 		}
 		else {
 			locationHashParts = locationHashParts[0].split("/i/");
 		}
 		if (locationHashParts.length > 1) {
 			anchorParts["item"] = locationHashParts[1];
 		}
 		else {
 			anchorParts["section"] = locationHashParts[0];
 		}
 		return anchorParts;
 	}

 	window.anchor = function (section, item) {
 		var anchor = "#";
 		if (section != null) {
 			anchor += "/s/" + section;
 		}
 		if (item != null) {
 			anchor += "/i/" + item;
 		}
 		return anchor;
 	}

 	window.onModelCancelClick = function (modelDiv) {
		modelDiv.style.display='none';
		var pathParts = anchorParts(window.location.hash);
		history.pushState(null, null, anchor(pathParts["section"], null));
		scrollToSection();
 	}

 	window.onVideoModelCancelClick = function (modelDiv) {
 		var videoSource = $(modelDiv).find('source');
 		var src = videoSource.attr('src');
 		videoSource.attr('src', '');
 		videoSource.attr('src', src);
 		onModelCancelClick(modelDiv);
 	}

  window.onThumbnailClick = function (section, itemAnchor) {
		history.pushState(null, null, anchor(section, itemAnchor));
		document.getElementById(itemAnchor).style.display = 'inline';
  }

 	// window.anchorParts = function (locationHash) {
 	// 	var locationHashParts = locationHash.replace(/^#\//, "").split("/");
 	// 	var anchorParts = {
 	// 		"section": null,
 	// 		"item": null
 	// 	};
 	// 	if (locationHashParts[0] != "") {
 	// 		anchorParts["section"] = locationHashParts[0];
 	// 	}
 	// 	if (locationHashParts.length >= 2 && locationHashParts[1] != "") {
 	// 		anchorParts["item"] = locationHashParts[1];
 	// 	}
 	// 	return anchorParts;
 	// }

 	// window.anchor = function (section, item) {
 	// 	var anchor = "#/";
 	// 	if (section != null) {
 	// 		anchor += section;
 	// 	}
 	// 	if (item != null) {
 	// 		anchor += "/" + item;
 	// 	}
 	// 	return anchor;
 	// }

  // open modals if their id is in the url
  var pathParts = window.anchorParts(window.location.hash);

  if (pathParts["item"] != null) {
	  $('.wrapper').find('.w3-modal').each(function(index, modalDiv){
	  	if(pathParts["item"] == $(modalDiv).attr('id')) {
	  		var url = window.location.href;
	  		console.log(111, pathParts["section"]);
	  		$(window).scrollTop($("#"+pathParts["section"]).offset().top);
	  		$('#'+pathParts["item"]).show();
	  		history.pushState(null, null, window.anchor(pathParts["section"], pathParts["item"]));
	  	}
	  });
	}
	else if (pathParts["section"] != null) {
		$(window).scrollTop($("#"+pathParts["section"]).offset().top);
	}

  // open modals if their id is in the url for pages not included in the parallax(installations, bodyscapes, equilibrium)
  $('.equiwrapper, .amphiwrapper, .bodywrapper').find('.w3-modal').each(function(index, modalDiv){
  	var id = $(modalDiv).attr('id');
  	if(pathParts["item"] == id) {
  		$('#'+id).show();
  		history.pushState(null, null, window.anchor(pathParts["section"], pathParts["item"]));
  	}
  });

  //changes the url hash for the paralax page
  $(document).bind('scroll', function (e) {
   	var pathParts = anchorParts(window.location.hash);
   	if (pathParts["item"] == null) {
	   	$('.section').each(function(){
	   		if (
	   			$(this).offset().top < window.pageYOffset + 10
				//begins before top
				&& $(this).offset().top + $(this).height() > window.pageYOffset + 10
				//but ends in visible area
				//+ 10 allows you to change hash before it hits the top border
				){
	   			var hash = anchor($(this).attr('id'), null);
	   			if (window.location.hash != hash) {
	   				if(window.history.pushState) {
	   					window.history.pushState(null, null, hash);
	   				}
	   				else {
	   				  window.location.hash = hash;
	   				} 
	   			}
	   		}
	   	})
	   }
  });

   // $('.w3-hover-opacity').click(function(){
   // 	var id = $('.w3-modal').attr('id');
   // 	console.log(id);
   
   // })
   
	$(window).bind('popstate', function(e) {
		var pathParts = anchorParts(window.location.hash);
		if (pathParts['item'] == null) {
			$('.wrapper, .equiwrapper, .amphiwrapper, .bodywrapper').find('.w3-modal').each(function(index, modalDiv) {
				modalDiv.style.display = 'none';
			});
		}
		else {
			document.getElementById(pathParts['item']).style.display = 'inline';
		}
	});

});