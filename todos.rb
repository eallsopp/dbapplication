require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"

require_relative "databasepersistence"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

configure(:development) do
  require "sinatra/reloader"
  also_reload "databasepersistence.rb"
end

helpers do
  def list_class(list)
    "complete" if list_complete?(list)
  end

  def list_complete?(list)
    todos_count(list) > 0 && todos_remaining_count(list) == 0
  end

  def todos_remaining_count(list)
    list[:todos].select { |todo| !todo[:completed] }.size
  end

  def todos_count(list)
    list[:todos].size
  end

  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition {|list| list_complete?(list)}

    incomplete_lists.each(&block)
    complete_lists.each(&block)
  end

  def sort_todos(todos, &block)
    complete_todos, incomplete_todos = todos.partition { |todo| todo[:completed] }

    incomplete_todos.each(&block)
    complete_todos.each(&block)
  end

  def next_todo_id(todos)
    max = todos.map { |todo| todo[:id] }.max || 0
    max + 1
  end
end

before do
  @storage = DatabasePersistence.new(logger)
end

def load_list(id)
  list = @storage.find_list(id)
  return list if list

  session[:error] = "The specific list was not found."
  redirect "/lists"
end

#validates user input
def error_for_list_name(name)
  if !(1..100).cover? name.size
    "Enter a list between 1-100 characters"
  elsif @storage.all_lists.any? {|list| list[:name] == name }
     "List name must be unique."
  end
end

# validates todo input
def error_for_todo(name)
  if !(1..100).cover? name.size
    "Todo must be between 1-100 characters"
  end
end

get "/" do
  redirect "/lists"
end

#create a new list
post "/lists" do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    @storage.create_new_list(list_name)

    session[:success] = "The list has been created."
    # {session => {:lists => [{name: list_name, :todos => []}]},
    #             {:success => "The list has been created."},
    redirect "/lists"
  end
end

#view all of the lists
get "/lists" do
  @lists = @storage.all_lists
  erb :lists, layout: :layout
end

#render new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

#view a todo list
get "/lists/:id" do
  id = params[:id].to_i
  list = @storage.find_list(id)
  @list = list
  @list_name = list[:name]
  @list_id = list[:id]
  @todos = list[:todos]
  erb :list, layout: :layout
end

#edit existing todo list
get "/lists/:id/edit" do
  id = params[:id].to_i
  @list = @storage.find_list(id)
  erb :edit_list, layout: :layout
end

#update an existing todo list
post "/lists/:id" do
  list_name = params[:list_name].strip
  id = params[:id].to_i
  @list = @storage.find_list(id)

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @storage.update_list_name(id, list_name)
    session[:success] = "The list has been updated."
    redirect "/lists/#{id}"
  end
end

#delete a todo list
post "/lists/:id/destroy" do
  id = params[:id].to_i
  @storage.delete_todo_list(id)
  session[:success] = "The list has been deleted."
  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    redirect "/lists"
  end
end

#add a new todo to a list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list = @storage.find_list(@list_id)
  text = params[:todo].strip

  error = error_for_todo(text)
    if error
      session[:error] = error
      erb :list, layout: :layout
    else
      @storage.create_new_todo(@list_id, text)

      session[:success] = "The todo item has been added."
      redirect "/lists/#{@list_id}"
    end
end

#delete a todo from a given list
post "/lists/:list_id/todos/:id/destroy" do
  @list_id = params[:list_id].to_i
  @list = @storage.find_list(@list_id)

  todo_id = params[:id].to_i
  @storage.delete_todo_from_list(@list_id, todo_id)

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    session[:success] = "The todo has been deleted."
    redirect "/lists/#{@list_id}"
  end
end


#update status of todo
post "/lists/:list_id/todos/:id" do
  @list_id = params[:list_id].to_i
  @list = @storage.find_list(@list_id)

  todo_id = params[:id].to_i
  is_completed = params[:completed] == "true"
  @storage.update_todo_status(@list_id, todo_id, is_completed)

  session[:success] = "The todo has been updated."
  redirect "/lists/#{@list_id}"
end

#complete all items in the todo list
post "/lists/:id/complete_all" do
  @list_id = params[:id].to_i
  @list = @storage.find_list(@list_id)

  @storage.mark_all_todos_completed(@list_id)

  session[:success] = "All todos have been completed."
  redirect "/lists/#{@list_id}"
end

after do
  @storage.disconnect
end
