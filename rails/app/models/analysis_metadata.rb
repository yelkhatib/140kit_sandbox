class AnalysisMetadata < ActiveRecord::Base
  self.table_name = "analysis_metadatum"
  belongs_to :curation
  belongs_to :analytical_offering
  has_many :analytical_offering_variables
  has_many :graphs
  def status
    if self.finished
      return "Finished"
    elsif !self.finished && self.ready && self.locked?
      "Analyzing"
    elsif !self.finished && self.ready && self.curation.status == "imported"
      "Processing"
    elsif !self.ready && self.curation.status == "imported"
      return "Verifying"
    elsif self.ready && self.curation.status == "imported"
      return "Processing"
    elsif self.ready && (self.curation.status == "tsv_stored" || self.curation.status == "needs_import")
      return "Waiting on Import"
    else return "Unknown"
    end
  end
  
  def printed_variables
    if !variables.empty?
      return "("+variables.collect{|variable| "<b>#{variable.name}</b>: #{variable.value}"}.join(" | ")+")"
    else
      return ""
    end
  end
  
  def locked?
    lock = Lock.find_by_classname_and_with_id("AnalysisMetadata", self.id)
    return !lock.nil?
  end

  def links
    links = []
    if self.finished
      links << "<a href='/analytics/#{self.id}'>Results</a>"
    elsif !self.finished && self.ready && self.locked?
      links << "Analyzing"
    elsif !self.finished && self.ready && self.curation.status == "imported"
      links << "Processing"
    elsif !self.ready && self.curation.status == "imported"
      links << "<a href='/analytics/#{self.id}'>Results</a>"
    elsif self.ready && self.curation.status == "imported"
      links << "<a href='/analytics/#{self.id}'>Results</a>"
    end
    return links
  end

  def verify_absolute_uniqueness
    duplicate_analysis_metadatas = AnalysisMetadata.where(:curation_id => self.curation_id, :analytical_offering_id => self.analytical_offering.id, :finished => false).select{|analysis_metadata| analysis_metadata.run_vars==self.run_vars}-[self]
    results = {:success => true}
    if !duplicate_analysis_metadatas.empty?
      results[:reason] = "Found an exact duplicate of this analysis metadata. This one will now be deleted. Only one analysis metadata of exact variables is permitted at a time."
      results[:success] = false
      self.variables.collect{|variable| variable.destroy}
      self.curation.analysis_metadatas = self.curation.analysis_metadatas-[self]
      self.destroy
    end
    return results
  end

  def run_vars
    return variables.collect{|v| v.value}
  end
  
  def variables
    return analytical_offering_variables.sort{|x,y| x.position<=>y.position}
  end

  
  def datamapper_dumped_object(value)
    [ Marshal.dump(value) ].pack('m')
  end
  def set_variables!
    self.set_variables.each do |v|
      v.value = self.function_class.default_variables[self.set_variables.index(v)] if v.value.nil?
      v.save!
    end
  end
  
  def set_variable(analytical_offering_variable)
    case analytical_offering_variable.name
    when "curation_id"
      return curation_id
    else
      function_class.set_variables(self, analytical_offering_variable, Curation.find_by_id(curation_id))
    end
  end

  def self.set_variables(analysis_metadata, analytical_offering_variable, curation)
    return ""
  end

  def verify_variable(analytical_offering_variable, answer)
    return function_class.verify_variable(self, analytical_offering_variable, answer).merge({:analytical_offering_variable_descriptor_id => analytical_offering_variable.id})
  end
  
  def self.verify_variable(metadata, variable_descriptor, answer)
    #if it got sent here, then it means that the analytical offering has not determined its own independent
    #verification process for the given variable.
    return {:variable => answer}
  end

  def title
    return analytical_offering.title
  end
  
  def language
    return analytical_offering.language
  end

  def created_by
    return analytical_offering.created_by
  end

  def created_by_link
    return analytical_offering.created_by_link
  end

  def source_code_link
    return analytical_offering.source_code_link
  end

  def function
    return analytical_offering.function
  end
  
  def function_class
    begin
      return function.classify.constantize
    rescue
      load File.dirname(__FILE__) + "/../../../code/analyzer/tools/#{function}#{AnalyticalOffering.language_extensions(self.analytical_offering.language)}"
      retry
    end
  end
  
  def function_path
    File.dirname(__FILE__) + "/../../../code/analyzer/tools/#{function}#{AnalyticalOffering.language_extensions(self.analytical_offering.language)}"
  end
  
  def clear
    function_class.clear(self)
  end
  
  def self.view(curation, params)
    return {:response => "<h1>Sorry!</h1><p>It looks like this developer has not created a viewable result for this analytic yet</p>", :found => false}
  end

end

require_all File.dirname(__FILE__) + '/../../../code/analyzer/tools'