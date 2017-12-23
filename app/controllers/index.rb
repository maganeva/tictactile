get '/' do

  # def architecture
  #   @arch = []
  #   @title = ['zero','Residence 2003 / D&D Harvey Architects, East Hampton, NY',
  #     'Residence 2003 / D&D Harvey Architects, East Hampton, NY',
  #     'Residence 2005 / D&D Harvey Architects, East Hampton, NY',
  #     'Residence 2003 / D&D Harvey Architects, East Hampton, NY',
  #     'Residence 2004 / D&D Harvey Architects, East Hampton, NY',
  #     'Watch Store / Project with Genius Mad Architects, Sofia, Bulgaria',
  #     'Watch Store 1999 / Project with Genius Mad Architects, Sofia, Bulgaria',
  #     'Residence / Project with Genius Mad Architects, Sofia, Bulgaria',
  #     'Residence / Project by Genius Mad Architects, Sofia, Bulgaria',
  #     'Business Center / GM Architects, Sofia, Bulgaria',
  #     'Lighthouse Cafe',
  #     'HHJA - poster 2009',
  #     'Restaurant',
  #     'Business Center',
  #     'Memorial Building'
  #     ]


  #     (1..15).each do |n|
  #       @arch << {thumbnail: "img/Arch/#{n}.jpg",
  #               image: "img/Arch/-#{n}.jpg",
  #               title: @title[n]
  #               }
  #     end
  #     p @arch
  # end

  # @arch = architecture




  @arch = [
    {thumbnail: 'img/Arch/1.jpg',
      image: 'img/Arch/-1.jpg',
      title: 'Residence 2003 / D&D Harvey Architects, East Hampton, NY'}, 
    {thumbnail: "img/Arch/2.jpg",
      image: 'img/Arch/-2.jpg',
      title: 'Residence 2003 / D&D Harvey Architects, East Hampton, NY'},
    {thumbnail: "img/Arch/3.jpg",
      image: 'img/Arch/-3.jpg',
      title: 'Residence 2005 / D&D Harvey Architects, East Hampton, NY'},
    {thumbnail: "img/Arch/4.jpg",
      image: 'img/Arch/-4.jpg',
      title: 'Residence 2003 / D&D Harvey Architects, East Hampton, NY'},
    {thumbnail: "img/Arch/5.jpg",
      image: 'img/Arch/-5.jpg',
      title: 'Residence 2004 / D&D Harvey Architects, East Hampton, NY'},
    {thumbnail: "img/Arch/6.jpg",
      image: 'img/Arch/-6.jpg',
      title: 'Watch Store / Project with Genius Mad Architects, Sofia, Bulgaria'},
    {thumbnail: "img/Arch/7.jpg",
      image: 'img/Arch/-7.jpg',
      title: 'Watch Store 1999 / Project with Genius Mad Architects, Sofia, Bulgaria'},
    {thumbnail: "img/Arch/8.jpg",
      image: 'img/Arch/-8.jpg',
      title: 'Residence / Project with Genius Mad Architects, Sofia, Bulgaria'},
    {thumbnail: "img/Arch/9.jpg",
      image: 'img/Arch/-9.jpg',
      title: 'Residence / Project by Genius Mad Architects, Sofia, Bulgaria'},
    {thumbnail: "img/Arch/10.jpg",
      image: 'img/Arch/-10.jpg',
      title: 'Business Center / GM Architects, Sofia, Bulgaria'},
    {thumbnail: "img/Arch/11.jpg",
      image: 'img/Arch/-11.jpg',
      title: 'Lighthouse Cafe'},
    {thumbnail: 'img/Arch/12.jpg',
      image: 'img/Arch/-12.jpg',
      title: 'HHJA - poster 2009'},
    {thumbnail: 'img/Arch/13.jpg',
      image: 'img/Arch/-13.jpg',
      title: 'Restaurant'},
    {thumbnail: 'img/Arch/14.jpg',
      image: 'img/Arch/-14.jpg',
      title: 'Business Center'},
    {thumbnail: 'img/Arch/15.jpg',
      image: 'img/Arch/-15.jpg',
      title: 'Memorial Building'},
      {thumbnail: 'img/Arch/16.jpg',
      image: 'img/Arch/-16.jpg',
      title: 'Parametric Experiment'}
    ]


    @digital = [
    {thumbnail: 'img/Digitalart/1.jpg',
      image: 'img/Digitalart/-1.jpg',
      title: 'Mnemonic Revision 2007'},
    {thumbnail: 'img/Digitalart/2.jpg',
      image: 'img/Digitalart/-2.jpg',
      title: 'Cadence 2007'},
    {thumbnail: 'img/Digitalart/3.jpg',
      image: 'img/Digitalart/-3.jpg',
      title: 'Age Again 2006'},
    {thumbnail: 'img/Digitalart/4.jpg',
      image: 'img/Digitalart/-4.jpg',
      title: 'Again 2006'},
    {thumbnail: 'img/Digitalart/5.jpg',
      image: 'img/Digitalart/-5.jpg',
      title: 'Sources 2006'},
    {thumbnail: 'img/Digitalart/6.jpg',
      image: 'img/Digitalart/-6.jpg',
      title: 'Retrieve 2006'},
    {thumbnail: 'img/Digitalart/7.jpg',
      image: 'img/Digitalart/-7.jpg',
      title: 'Trend 2006'},
    {thumbnail: 'img/Digitalart/8.jpg',
      image: 'img/Digitalart/-8.jpg',
      title: 'Emerge 2006'},
    {thumbnail: 'img/Digitalart/9.jpg',
      image: 'img/Digitalart/-9.jpg',
      title: 'Seek 2006'},
    {thumbnail: 'img/Digitalart/10.jpg',
      image: 'img/Digitalart/-10.jpg',
      title: 'Panoptic Prognosticon 2004'},
    {thumbnail: 'img/Digitalart/11.jpg',
      image: 'img/Digitalart/-11.jpg',
      title: ''},
    {thumbnail: 'img/Digitalart/12.jpg',
      image: 'img/Digitalart/-12.jpg',
      title: 'Metronoming Solitude 2004'},
    {thumbnail: 'img/Digitalart/13.jpg',
      image: 'img/Digitalart/-13.jpg',
      title: 'Ubiquitous Soldier 2004'},
    {thumbnail: 'img/Digitalart/14.jpg',
      image: 'img/Digitalart/-14.jpg',
      title: '4G Warfare / Next Generation Witch Hunt 2004'},
    {thumbnail: 'img/Digitalart/15.jpg',
      image: 'img/Digitalart/-15.jpg',
      title: '1001 Lies 2004'},
    {thumbnail: 'img/Digitalart/16.jpg',
      image: 'img/Digitalart/-16.jpg',
      title: 'Once Upon a Timequake 2004'},
    {thumbnail: 'img/Digitalart/17.jpg',
      image: 'img/Digitalart/-17.jpg',
      title: 'Holy Mug/ Greeny Grail 2004'},
    {thumbnail: 'img/Digitalart/18.jpg',
      image: 'img/Digitalart/-18.jpg',
      title: 'Hold 2005'},
    {thumbnail: 'img/Digitalart/19.jpg',
      image: 'img/Digitalart/-19.jpg',
      title: 'Shellout Falter 2004'},
    {thumbnail: 'img/Digitalart/20.jpg',
      image: 'img/Digitalart/-20.jpg',
      title: '011 2004'},
    {thumbnail: 'img/Digitalart/21.jpg',
      image: 'img/Digitalart/-21.jpg',
      title: '2004'},
    {thumbnail: 'img/Digitalart/22.jpg',
      image: 'img/Digitalart/-22.jpg',
      title: 'Poster'}
      ]


    @sketches = [
    {thumbnail: 'img/Art/1.jpg',
      image: 'img/Art/-1.jpg',
      title: 'Untitled 2009'},
    {thumbnail: 'img/Art/2.jpg',
      image: 'img/Art/-2.jpg',
      title: "Escher's Tune 2003"},
    {thumbnail: 'img/Art/3.jpg',
      image: 'img/Art/-3.jpg',
      title: 'Age Again 2006'},
    {thumbnail: 'img/Art/4.jpg',
      image: 'img/Art/-4.jpg',
      title: 'Untitled 2009'},
    {thumbnail: 'img/Art/5.jpg',
      image: 'img/Art/-5.jpg',
      title: 'untitled'},
    {thumbnail: 'img/Art/6.jpg',
      image: 'img/Art/-6.jpg',
      title: 'untitled'},
    {thumbnail: 'img/Art/7.jpg',
      image: 'img/Art/-7.jpg',
      title: 'untitled 2004'},
    {thumbnail: 'img/Art/8.jpg',
      image: 'img/Art/-8.jpg',
      title: 'untitled'},
    {thumbnail: 'img/Art/9.jpg',
      image: 'img/Art/-9.jpg',
      title: 'untitled'},
    {thumbnail: 'img/Art/10.jpg',
      image: 'img/Art/-10.jpg',
      title: 'untitled'}
    ] 
erb :'index'

end

get '/amphibians' do

@amphibians = [
    {thumbnail: 'img/Install/amphibians2002/1.jpg',
      image: 'img/Install/amphibians2002/-1.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/2.jpg',
      image: 'img/Install/amphibians2002/-2.jpg',
      title: 'Total Sale / Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/3.jpg',
      image: 'img/Install/amphibians2002/-3.jpg',
      title: 'Master / Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/4.jpg',
      image: 'img/Install/amphibians2002/-4.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/5.jpg',
      image: 'img/Install/amphibians2002/-5.jpg',
      title: 'Intentional Coincidences/ Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/6.jpg',
      image: 'img/Install/amphibians2002/-6.jpg',
      title: 'No home / Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/7.jpg',
      image: 'img/Install/amphibians2002/-7.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/8.jpg',
      image: 'img/Install/amphibians2002/-8.jpg',
      title: 'Amphibians S scape 2003 '},
    {thumbnail: 'img/Install/amphibians2002/9.jpg',
      image: 'img/Install/amphibians2002/-9.jpg',
      title: 'Leader / Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/10.jpg',
      image: 'img/Install/amphibians2002/-10.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/11.jpg',
      image: 'img/Install/amphibians2002/-11.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/12.jpg',
      image: 'img/Install/amphibians2002/-12.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/13.jpg',
      image: 'img/Install/amphibians2002/-13.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/14.jpg',
      image: 'img/Install/amphibians2002/-14.jpg',
      title: 'Amphibians S scape 2003'},
    {thumbnail: 'img/Install/amphibians2002/15.jpg',
      image: 'img/Install/amphibians2002/-15.jpg',
      title: 'Amphibians S scape 2003'},
    ] 

  erb :'amphibians'
end

get '/bodyscapes' do 
  erb :'bodyscapes'
end

get '/equil' do
  erb :'equil'
end

# get '/digital' do
#   erb :'digital'
# end

get '/three' do
  erb :'three'
end

