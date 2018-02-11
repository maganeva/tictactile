> **Note**: Portfolio site of the world acclaimed architect and artist 'tictactile'. Static resources like videos and images are not uploaded to GitHub.

### [tictactile.com](http://www.tictactile.net)


### development

To start the development environment on Windows:

From the Windows search bar, type `Command Prompt with Ruby and Rails`

Press enter to open the Command Prompt window

You will be greeted with a prompt like:
```
C:\Sites>
```

Go to the tictactile directory by entering the following two commands:
```
d:
cd \website\git\tictactile
```

Open the Sublime Text editor by entering the following command:
```
subl .
```

Start the local development webserver by entering the following command:
```
bundle exec puma
```

While the local development server is running, you can preview changes by opening the following url in Chrome:
```
http://localhost:3000
```

Stop the local development server by either (a) closing the Command Prompt window in which server is running or (b) typing Ctrl+C and entering 'Y' twice at the prompts.

### to add an image or video to an existing collection

First, follow instructions in the [development](#development) section, above, to open the Sublime Text editor and to start the local development webserver.

In the FOLDERS pane at the left of the Sublime Text window, navigate to file `tictactile/app/controllers/index.rb`

This will open a tab labeled `index.rb` at the right of the Sublime Text window.  That file is where we associate an image file and captions with a particular page.  The `@arch`, `@digital`, `@sketches`, `@videos`, `@amphibians`, `@bodyscapes` and `@metapolis` lists define attributes of the items on a page.

The simplest way to add a new item is to copy-and-paste a similar item from the same list and then to modify the copy.  Go ahead and duplicate an item.

Change the `thumbnail` filename.

Change the `image` or `video` filename.

Change the `title`

Change the `item_anchor`.  This is the text that will appear at the end of the URL when you've clicked the item.  It should be unique.  Scan all of the lists to ensure that your new value hadn't been used for another item's `item_anchor`.

Save the `index.rb` file.

Now use the Windows File Manager to place a copy of the thumbnail file and the image (or video) file in the appropriate folder beneath `D:\website\git\tictactile\public\`.  For example, a new digital art thumbnail and image will be copied to folder `D:\website\git\tictactile\public\img\Digitalart`.

To test the change, use Chrome to navigate to:
```
http://localhost:3000
```

If you had the relevant page open already in Chrome, use Shift+Reload to reload the page fully.

If the image or video doesn't display as you expect, see the [troubleshooting](#troubleshooting) section.

### troubleshooting

If the thumbnail image is broken in Chrome, ensure that the capitalization and path of the filename in the relevant `thumbnail` value in `tictactile/app/controllers/index.rb` is correct.

If the big image or video is broken in Chrome, ensure that the capitalization and path of the filename in the relevant `image` or `video` value in `tictactile/app/controllers/index.rb` is correct.

If the video doesn't play to the end, don't freak out.  This may be an artifact of the Windows development environment.  It will probably work when you deploy to the website.

If the video doesn't play on the website, you may need to transcode it with the option to optimize for web buffering enabled.

If the wrong image opens when you click a thumbnail, ensure that the `item_anchor` values for the two items are different.

If either the thumbnail or the image is renders too big or too small, you may have to add or remove the `override_thumbnail_class` or `override_image_class` properties for the item.  Try to follow the example of another item that's tall or wide.