class Projects::ProjectMembersController < Projects::ApplicationController
  include AccessRequestActions

  # Authorize
  before_action :authorize_admin_project_member!, except: [:index, :leave, :request_access]

  def index
    @project_members = @project.project_members
    @project_members = @project_members.non_pending unless can?(current_user, :admin_project, @project)

    if params[:search].present?
      users = @project.users.search(params[:search]).to_a
      @project_members = @project_members.where(user_id: users)
    end

    @project_members = @project_members.order('access_level DESC')

    @group = @project.group

    if @group
      @group_members = @group.group_members
      @group_members = @group_members.non_pending unless can?(current_user, :admin_group, @group)

      if params[:search].present?
        users = @group.users.search(params[:search]).to_a
        @group_members = @group_members.where(user_id: users)
      end

      @group_members = @group_members.order('access_level DESC')
    end

    @project_member = @project.project_members.new
    @project_group_links = @project.project_group_links
  end

  def create
    @project.team.add_users(params[:user_ids].split(','), params[:access_level], current_user)

    redirect_to namespace_project_project_members_path(@project.namespace, @project)
  end

  def update
    @project_member = @project.project_members.find(params[:id])

    return render_403 unless can?(current_user, :update_project_member, @project_member)

    @project_member.update_attributes(member_params)
  end

  def destroy
    @project_member = @project.project_members.find(params[:id])

    return render_403 unless can?(current_user, :destroy_project_member, @project_member)

    @project_member.request? ? @project_member.decline_request : @project_member.destroy

    respond_to do |format|
      format.html do
        redirect_to namespace_project_project_members_path(@project.namespace, @project)
      end
      format.js { head :ok }
    end
  end

  def resend_invite
    redirect_path = namespace_project_project_members_path(@project.namespace, @project)

    @project_member = @project.project_members.find(params[:id])

    if @project_member.invite?
      @project_member.resend_invite

      redirect_to redirect_path, notice: 'The invitation was successfully resent.'
    else
      redirect_to redirect_path, alert: 'The invitation has already been accepted.'
    end
  end

  def leave
    @project_member =
      @project.project_members.find_by(user_id: current_user.id) ||
      @project.project_members.find_by(created_by_id: current_user.id)

    if can?(current_user, :destroy_project_member, @project_member)
      notice =
        if @project_member.request?
          'You withdrawn your access request to the project.'
        else
          'You left the project.'
        end
      @project_member.destroy

      redirect_to dashboard_projects_path, notice: notice
    else
      if current_user == @project.owner
        message = 'You can not leave your own project. Transfer or delete the project.'
        redirect_back_or_default(default: { action: 'index' }, options: { alert: message })
      else
        render_403
      end
    end
  end

  def apply_import
    source_project = Project.find(params[:source_project_id])

    if can?(current_user, :read_project_member, source_project)
      status = @project.team.import(source_project, current_user)
      notice = status ? "Successfully imported" : "Import failed"
    else
      return render_404
    end

    redirect_to(namespace_project_project_members_path(project.namespace, project),
                notice: notice)
  end

  protected

  def member_params
    params.require(:project_member).permit(:user_id, :access_level)
  end

  # AccessRequestActions concern
  def access_requestable_resource
    @project
  end

  def access_requestable_resource_path
    namespace_project_path(@project.namespace, @project)
  end

  def access_requestable_resource_members_path
    namespace_project_project_members_path(@project.namespace, @project)
  end
end
