$(document).ready(function(){

	window.showMenuSidebar = function () {
		$("#MainMenu").css("left","0px");
		function showMenu(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,100% 100%,0% 100%)");
			$("#MenuIcon").animate({left:'-100'},300);
		}
		setTimeout(showMenu,100);
	}

	$("#MenuIcon, #home").click(window.showMenuSidebar);


	$("#close").click(function(){
		$("#MainMenu").css("-webkit-clip-path","polygon(0 0,0% 0,100% 100%,0% 100%)");
		function hideMenu(){
			$("#MainMenu").css("left","-300px");
			$("#MenuIcon").animate({left:'30'},300);
		}
		setTimeout(hideMenu, 300);

		function originallayout(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,0% 100%,0% 100%)");
		}
		setTimeout(originallayout, 600);
	});


	$(".menuitem").click(function(){
		$("#MainMenu").css("-webkit-clip-path","polygon(0 0,0% 0,100% 100%,0% 100%)");
		function hideMenu(){
			$("#MainMenu").css("left","-300px");
			$("#MenuIcon").animate({left:'30'},300);
		}
		setTimeout(hideMenu, 300);

		function originallayout(){
			$("#MainMenu").css("-webkit-clip-path","polygon(0 0,100% 0,0% 100%,0% 100%)");
		}
		setTimeout(originallayout, 600);
	});

	$(window).resize(function (e) {
		if (window.resizeAnimationTimeout != null) {
			window.clearTimeout(window.resizeAnimationTimeout);
		}
		window.resizeAnimationTimeout = window.setTimeout(function () {
			var w = $(window);
			startAnimation(
				document.getElementById("home"),
				w.width(),
				w.height());
		}, 200);
	});

	window.resizeAnimationTimeout = null;

 	window.anchorParts = function (locationHash) {
 		const DEBUG = false;
 		var debugTrace = [];
 		var locationHashParts = locationHash.split('#');
 		var anchorParts = {
 			"section": null,
 			"item": null
 		};
 		if (locationHashParts.length > 1) {
 			debugTrace.push(11);
 			locationHashParts = locationHashParts[1].split("/s/");
 		}
 		if (locationHashParts.length > 1) {
 			debugTrace.push(22);
 			locationHashParts = locationHashParts[1].split("/i/");
 			anchorParts["section"]=locationHashParts[0]
 		}
 		else {
 			debugTrace.push(33);
 			locationHashParts = locationHashParts[0].split("/i/");
 		}
 		if (locationHashParts.length > 1) {
 			debugTrace.push(44);
 			anchorParts["item"] = locationHashParts[1];
 		}
 		else if (locationHashParts[0] != "") {
 			debugTrace.push(55);
 			anchorParts["section"] = locationHashParts[0];
 		}
 		if (DEBUG) {
 			console.log(debugTrace);
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
		onScroll();
 	}

 	window.onVideoModelCancelClick = function (modelDiv) {
 	  var video = $(modelDiv).find('video').get(0);
 	  video.pause();
 	  video.load();
 	  onModelCancelClick(modelDiv);
 	}

  window.onThumbnailClick = function (section, itemAnchor) {
    history.pushState(null, null, anchor(section, itemAnchor));
    showModalItem(itemAnchor);
  }
	
  window.onVideoThumbnailClick = function (section, itemAnchor) {
    history.pushState(null, null, anchor(section, itemAnchor));
		showModalVideoItem(itemAnchor);
  }

  window.onNextModalClick = function (event, section, currentItemAnchor, newItemAnchor) {
    if (event != null) {  
      event.stopPropagation();
    }
    showNextModalItem(section, currentItemAnchor, newItemAnchor);
  }

  window.isIndexPage = function () {
    return (window.location.pathname == '/');
  }

  window.onMenuItemClick = function (event, section) {
    if (isIndexPage()) {
      document.getElementById(section).scrollIntoView({behavior: "smooth"});
    }
    else {
      window.location.href = '/' + anchor(section);
    }
  }

  window.showNextModalItem = function (section, currentItemAnchor, newItemAnchor) {
    document.getElementById(currentItemAnchor).style.display = 'none';
    showModalItem(newItemAnchor);
    history.pushState(null, null, anchor(section, newItemAnchor));
  }

  window.showNextModalItemViaKeydown = function (newItemAnchorAttributeName) {
    if (displayedAnchor in window) {
      var displayedItem = document.getElementById(window.displayedAnchor)
      var section = displayedItem.getAttribute("data-section");
      var newItemAnchor = displayedItem.getAttribute(newItemAnchorAttributeName);
      if (newItemAnchor != '') {
        showNextModalItem(section, window.displayedAnchor, newItemAnchor);
      }
    }
  }

  window.showModalItem = function (itemAnchor) {
	  document.getElementById(itemAnchor).style.display = 'inline';
	  window.displayedAnchor = itemAnchor;
	}

  window.showModalVideoItem = function (itemAnchor) {
    var modelDiv = document.getElementById(itemAnchor);
		var source = $(modelDiv).find('source').get(0);
		var videoUrl = source.getAttribute("data-video-url");
    if (source.getAttribute("src") != videoUrl) {
      var video = $(modelDiv).find('video').get(0);
      video.pause();
      source.setAttribute("src", videoUrl);
      video.load();		
    }
    showModalItem(itemAnchor);
  }

  $(window).on('hashchange', function() {
	if (displayedAnchor in window) {
	  var pathParts = anchorParts(window.location.hash);
	  document.getElementById(window.displayedAnchor).style.display = 'none';
	  window.showModalItem(pathParts.item);
	}
  });

  window.onScroll = function () {
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
  }

 	

  // open modals if their id is in the url
  var pathParts = window.anchorParts(window.location.hash);

  if (pathParts["item"] != null) {
	  $('.wrapper').find('.w3-modal').each(function(index, modalDiv){
	  	if (pathParts["item"] == $(modalDiv).attr('id')) {
	  		var url = window.location.href;
	  		$(window).scrollTop($("#"+pathParts["section"]).offset().top);
				if (pathParts["section"] == "videos") {
					window.showModalVideoItem(pathParts["item"]);
				}
				else {
					window.showModalItem(pathParts["item"]);
				}
				
	  		history.pushState(null, null, window.anchor(pathParts["section"], pathParts["item"]));
	  	}
	  });
	}
	else if (window.isIndexPage()) {
		// ^^^ Open menu only on the index page, not on 'installations' pages
		// Open menu for empty section or 'home' section
		if (pathParts["section"] == null) {
			window.showMenuSidebar();
		}
		else {
			$(window).scrollTop($("#"+pathParts["section"]).offset().top);
			if (pathParts["section"] == "home") {
				window.showMenuSidebar();
			}
		}
	}

  // open modals if their id is in the url for pages not included in the parallax(installations, bodyscapes, equilibrium)
  $('.equiwrapper, .amphiwrapper, .bodywrapper').find('.w3-modal').each(function(index, modalDiv){
  	var id = $(modalDiv).attr('id');
  	if(pathParts["item"] == id) {
		window.showModalItem(pathParts["item"]);
  		history.pushState(null, null, window.anchor(pathParts["section"], pathParts["item"]));
  	}
  });

  //changes the url hash for the paralax page
  $(document).bind('scroll', function (e) {
  	window.onScroll();
  });

  $(document).bind('keydown', function (e) {
    var arrow = { left: 37, right: 39 };

    switch (e.which) {
      case arrow.left:
		window.showNextModalItemViaKeydown("data-previous-item-anchor");
        break;
	  case arrow.right:
		window.showNextModalItemViaKeydown("data-next-item-anchor");
        break;
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
			window.showModalItem(pathParts["item"]);  
		}
	});


});